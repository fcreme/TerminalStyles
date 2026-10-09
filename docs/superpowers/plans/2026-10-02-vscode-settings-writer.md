# VS Code Settings Writer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A style applied in a VS Code-family integrated terminal (VS Code, Insiders, VSCodium, Cursor, Windsurf) persists. It is written into that editor's `settings.json` after the user agrees once per editor, and every way of taking it off puts the file back exactly.

**Architecture:** `lib/vscode.ps1` is the existing pure text engine and stays unchanged. A new `lib/vscodewriter.ps1` owns all VS Code file I/O:
- target resolution;
- a per-editor state file (`vscode-state.json`) holding the consent answer and the undo record;
- the publisher and the reset;
- a testable picker preview session;
- `tstyles vscode [on|off]`.

The existing entry points call it the way they call the WezTerm writer: `Apply-StyleNonWT`, `Reset-StyleNonWT`, the picker and uninstall. `Get-TerminalCapability` reads the same decider the writer acts on, so the "can't show" notice and the write cannot disagree.

**Tech Stack:** PowerShell (Windows PowerShell 5.1 and pwsh 7), Pester 5/6, the repo's text-splicing JSONC editor in `lib/jsonctext.ps1`.

**Spec:** `docs/superpowers/specs/2026-10-02-vscode-settings-writer-design.md`. Read it in full, including **Revisions during planning** at the end, which overrides the sections above it.

## Global Constraints

- **Two engines.** Every line must run on Windows PowerShell 5.1 and pwsh 7. That rules out `?:`, `??`, `?.`, `&&`, `||` and .NET-Core-only APIs (CONTRIBUTING.md).
- **ASCII string literals.** New `.ps1` string literals are ASCII only: write `--`, never an em dash. Windows PowerShell 5.1 reads BOM-less `.ps1` files in the system codepage and fails to parse non-ASCII string literals.
- **Plain commits.** No `Co-Authored-By`, no `Claude-Session`, no "Generated with" footer. The maintainer is the author of record.
- **Branch.** Work on `feat/vscode-settings-writer`, which already exists with the spec commits. Commit after every task.
- **Splats.** Every splat variable must be assigned in its own scope (`tests/Splat-Variables-Defined.Tests.ps1`). A splat of an undefined variable binds the first positional parameter to `''` and fakes a sandbox.
- **Never wrap a comma-return in `@()`.** `Get-JsoncObjectMember`, `Get-VSCodeColorOverride` and `Get-VSCodeStylePlan` return `,$arr`, and `@(...)` around such a call is an array of one. Assign the result instead.
- **Statuses are words.** Never collapse a status into a boolean. A message is printed only on the path where it is true (CLAUDE.md).
- **Tests never touch a real editor's files.**
  - Every test that reaches VS Code code either mocks `Resolve-VSCodeTarget` to a `$TestDrive` path, or binds all three of `-HomeDir`, `-AppData` and `-XdgConfigHome`.
  - It also points `$script:TStylesDataRoot` at `$TestDrive`, because that is where `vscode-state.json` lives.
  - `Confirm-Action` is mocked, never answered.
- **Running a test file:**
  ```
  pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/<File>.Tests.ps1 -Output Detailed"
  ```
  The suite runs from the repo root, `/Users/cremerius/TerminalStyles`.
- **No new state file anywhere else.** `vscode-state.json` lives under `$script:TStylesDataRoot` and nowhere else.

## Review Focus

These are the five inputs the spec implies but does not spell out, most likely to bite first. Each has a test in the task named.

1. **A settings.json with CRLF line endings** (last saved on Windows): apply then reset returns it byte for byte, CRLF intact. → Task 4.
2. **A settings.json with a UTF-8 BOM**: the BOM survives apply and reset, not just the picker's Esc. → Task 4.
3. **VS Code reformats the file between apply and reset** (settings UI, Sync, re-indent): reset still removes every key whose value text is unchanged, and names none as kept. → Task 4.
4. **`Code - Insiders`**, a variant name with spaces, as a state-file key: it round-trips. → Task 1.
5. **Picker Enter or Esc with nothing previewed**: Enter is a plain apply, and Esc writes nothing (mtime unchanged). → Task 7.

## File map

| File | Change | Responsibility |
|---|---|---|
| `lib/vscodewriter.ps1` | create | All VS Code file I/O: target, state, consent, publish, reset, picker session, `tstyles vscode`, uninstall targets |
| `tests/VSCode-Writer.Tests.ps1` | create | Behaviour of everything above, plus the wiring into the existing commands |
| `terminals.ps1` | modify | VSCode capability arm, `Get-UnsupportedStyleField` cursor nuance, Persist comment |
| `lib/fonts.ps1` | modify | `tstyles font` names WezTerm's `config.font` route only on WezTerm |
| `lib/applystyle.ps1` | modify | `Apply-StyleNonWT` asks then publishes; `Reset-StyleNonWT` resets VS Code |
| `tstyles.ps1` | modify | Picker wiring, `vscode` dispatch, `$script:TStylesSubcommands` |
| `lib/help.ps1` | modify | `reset` / `uninstall` detail, new `vscode` topic |
| `lib/update.ps1` | modify | Uninstall lists and undoes saved VS Code styles; sign-off names Windows Terminal |
| `tests/Get-TerminalCapability.Tests.ps1` | modify | Four writers; the VS Code flags with the writer on and off |
| `tests/Font-ApplyPromise.Tests.ps1` | modify | Pin `Test-VSCodeWriterActive` so the developer's own state cannot decide the result |
| `tests/Aa-RealStateBaseline.Tests.ps1`, `tests/Zz-RealStateUntouched.Tests.ps1` | modify | Fingerprint the five editors' real `settings.json` |
| `README.md`, `CHANGELOG.md`, `CLAUDE.md` | modify | Docs, changelog, "four writers" |

---

### Task 1: State store and target resolution

**Files:**
- Create: `lib/vscodewriter.ps1`
- Create: `tests/VSCode-Writer.Tests.ps1`

**Interfaces:**
- Consumes (existing):
  - `Get-VSCodeVariant [-AskpassNode] [-GitAskpass]` → variant string or `$null`.
  - `Get-VSCodeSettingsPath -Variant [-HomeDir] [-AppData] [-XdgConfigHome]` → path string.
  - `Get-JsoncToken -Text`, `Find-JsoncRootObject -Tokens`, `Find-JsoncCloseBrace -Tokens -OpenIndex`.
  - `Write-SettingsAtomic -Path -Json`.
  - `Invoke-VSCodeStyleApply` / `Invoke-VSCodeStyleReset`, used only by the tests here.
- Produces:
  - `Get-VSCodeStatePath` → `<DataRoot>/vscode-state.json`.
  - `ConvertTo-VSCodeRecord -Parsed` → `@{ Style; Wrote = @(@{Path=[string[]];Literal;Had}); CreatedParents = @([string[]]) }` or `$null`.
  - `Read-VSCodeState` → `@{ Ok = [bool]; Path; Entries = @{ <variant> = @{ consent = 'yes'|'no'|''; settingsPath; record } } }`.
  - `Write-VSCodeState -Entries <hashtable>`, which throws on failure.
  - `Set-VSCodeStateEntry -Variant [-SettingsPath] [-Consent 'yes'|'no'] [-Record]`. Only bound parameters change, and it throws when the state cannot be read.
  - `Resolve-VSCodeTarget [-Variant] [-HomeDir] [-AppData] [-XdgConfigHome] [-AskpassNode] [-GitAskpass]` → `@{ Status = 'ok'|'unknownvariant'|'nodir'; Variant; Path }`.
  - `Read-VSCodeSettingsText -Path` → the text, or `''` when there is no file.
  - `Test-VSCodeSettingsReadable -Text` → `[bool]`.

- [ ] **Step 1: Write the failing tests**

Create `tests/VSCode-Writer.Tests.ps1`:

```powershell
# The VS Code settings WRITER: lib/vscodewriter.ps1, the half of the VS Code
# support that touches files. lib/vscode.ps1 is the pure text engine and is
# tested in VSCode-Settings.Tests.ps1; everything here is about what reaches
# disk, in what order, and what the user is told.
#
# Nothing here may resolve a real editor's settings.json. Every Describe either
# mocks Resolve-VSCodeTarget to a $TestDrive path or binds all three of its path
# seams, and sandboxes $script:TStylesDataRoot, which holds vscode-state.json.
# Confirm-Action is mocked, never answered.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Resolve-VSCodeTarget' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            # All three path seams, so no platform can fall through to a real
            # profile: macOS reads HomeDir, Linux XDG, Windows APPDATA.
            $script:seams = @{
                HomeDir       = $script:h
                AppData       = (Join-Path $script:h 'AppData/Roaming')
                XdgConfigHome = (Join-Path $script:h '.config')
            }
            $script:cursor = '/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh'
        }

        It 'refuses to guess when it cannot name the editor' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -AskpassNode '' -GitAskpass '' @s
            $t.Status  | Should -Be 'unknownvariant'
            $t.Variant | Should -BeNullOrEmpty
            $t.Path    | Should -BeNullOrEmpty -Because 'with no path, nothing can be written to the wrong one'
        }

        It 'says nodir, and creates nothing, when the editor has no User folder' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -AskpassNode $script:cursor -GitAskpass '' @s
            $t.Status  | Should -Be 'nodir'
            $t.Variant | Should -Be 'Cursor'
            [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($t.Path)) |
                Should -BeFalse -Because 'asking where the file is must not create its folder'
        }

        It 'is ok with a User folder and no settings.json in it yet' {
            $s = $script:seams
            $expected = Get-VSCodeSettingsPath -Variant 'Cursor' @s
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($expected)) -Force | Out-Null

            $t = Resolve-VSCodeTarget -AskpassNode $script:cursor -GitAskpass '' @s
            $t.Status | Should -Be 'ok'
            $t.Path   | Should -Be $expected
            [System.IO.File]::Exists($t.Path) | Should -BeFalse -Because 'VS Code creates it lazily, and so may we'
        }

        It 'takes a variant it is given instead of detecting one' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -Variant 'VSCodium' -AskpassNode '' -GitAskpass '' @s
            $t.Variant | Should -Be 'VSCodium'
            $t.Path    | Should -Be (Get-VSCodeSettingsPath -Variant 'VSCodium' @s)
        }

        It 'keeps a bound -HomeDir away from the real APPDATA and XDG_CONFIG_HOME' {
            # The sandbox rule CLAUDE.md states for ZDOTDIR, one level further:
            # on Windows Get-VSCodeSettingsPath prefers APPDATA, so -HomeDir
            # alone would still resolve to the operator's roaming profile.
            $t = Resolve-VSCodeTarget -Variant 'Code' -HomeDir $script:h
            $t.Path.StartsWith($script:h) | Should -BeTrue -Because "$($t.Path) must be inside the sandbox"
        }
    }
}

Describe 'the VS Code state store' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:koholint = Get-StyleDir -StyleName 'koholint'
        }

        It 'reads no file as empty, not as broken' {
            $s = Read-VSCodeState
            $s.Ok | Should -BeTrue
            $s.Entries.Count | Should -Be 0
        }

        It 'will not start over on top of a file it cannot read' {
            # It holds the only record of which keys went into a settings.json.
            # Replacing it would strand them.
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{not json', [System.Text.UTF8Encoding]::new($false))
            (Read-VSCodeState).Ok | Should -BeFalse
            { Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' } | Should -Throw
            [System.IO.File]::ReadAllText((Get-VSCodeStatePath)) | Should -BeExactly '{not json'
        }

        It 'treats a root that is not an object as unreadable too' {
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '[1,2]', [System.Text.UTF8Encoding]::new($false))
            (Read-VSCodeState).Ok | Should -BeFalse
        }

        It 'changes one editor and leaves the others as they were' {
            Set-VSCodeStateEntry -Variant 'Code'   -SettingsPath '/c/settings.json' -Consent 'yes'
            Set-VSCodeStateEntry -Variant 'Cursor' -SettingsPath '/u/settings.json' -Consent 'no'
            Set-VSCodeStateEntry -Variant 'Code'   -Consent 'no'

            $e = (Read-VSCodeState).Entries
            $e['Code'].consent        | Should -Be 'no'
            $e['Code'].settingsPath   | Should -Be '/c/settings.json'
            $e['Cursor'].consent      | Should -Be 'no'
            $e['Cursor'].settingsPath | Should -Be '/u/settings.json'
        }

        It 'round-trips a variant name with spaces in it' {
            Set-VSCodeStateEntry -Variant 'Code - Insiders' -Consent 'yes'
            (Read-VSCodeState).Entries['Code - Insiders'].consent | Should -Be 'yes'
        }

        It 'clears a record only when -Record is bound' {
            $a = Invoke-VSCodeStyleApply -Text '{}' -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' -Record $a.Record
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty -Because '-Record was not bound'
            Set-VSCodeStateEntry -Variant 'Code' -Record $null
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'brings a record back from the file that still undoes the apply byte for byte' {
            # The test the record never had: through JSON and back. Windows
            # PowerShell 5.1 is where this would break -- ConvertTo-Json stops
            # at depth 2 by default, and a one-element array can come back as
            # its bare element.
            $user = "{`n  // mine`n  `"terminal.integrated.cursorStyle`": `"block`",`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $user -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath '/x' -Record $a.Record

            $back = (Read-VSCodeState).Entries['Code'].record
            $back.Style | Should -Be 'koholint'
            (Invoke-VSCodeStyleReset -Text $a.Text -Record $back).Text | Should -BeExactly $user
        }

        It 'keeps a one-key path a path, not a string' {
            $a = Invoke-VSCodeStyleApply -Text '{}' -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Record $a.Record
            $font = @((Read-VSCodeState).Entries['Code'].record.Wrote |
                      Where-Object { $_.Path[0] -eq 'terminal.integrated.fontFamily' })
            $font.Count | Should -Be 1 -Because 'koholint sets a font face'
            ,$font[0].Path | Should -BeOfType [string[]]
            @($font[0].Path).Count | Should -Be 1
        }

        It 'keeps the parent it created, so the emptied block is still taken away' {
            $bare = "{`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $bare -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Record $a.Record
            $back = (Read-VSCodeState).Entries['Code'].record
            @($back.CreatedParents).Count | Should -Be 1
            (Invoke-VSCodeStyleReset -Text $a.Text -Record $back).Text | Should -BeExactly $bare
        }
    }
}

Describe 'Test-VSCodeSettingsReadable' {
    InModuleScope TerminalStyles {
        It 'reads <label> as <ok>' -ForEach @(
            @{ label = 'a blank file';       text = '';                        ok = $true  }
            @{ label = 'whitespace';         text = "  `n";                    ok = $true  }
            @{ label = 'an object';          text = '{ "a": 1 }';              ok = $true  }
            @{ label = 'a commented object'; text = "// mine`n{ `"a`": 1 }";   ok = $true  }
            @{ label = 'a truncated object'; text = '{ "a": 1 ';               ok = $false }
            @{ label = 'an array';           text = '[1, 2]';                  ok = $false }
        ) {
            Test-VSCodeSettingsReadable -Text $text | Should -Be $ok
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: every test FAILS. The errors say `The term 'Resolve-VSCodeTarget' is not recognized` (or `Read-VSCodeState`, `Test-VSCodeSettingsReadable`, and so on).

- [ ] **Step 3: Create `lib/vscodewriter.ps1`**

```powershell
# VS Code's integrated terminal, wired in: the file I/O, the consent, and the
# undo records that lib/vscode.ps1 deliberately has none of.
#
# lib/vscode.ps1 is pure -- text in, text out -- and stays that way: it is what
# the round-trip tests drive. Everything here is the part that touches the
# user's machine, and it keeps three rules
# (docs/superpowers/specs/2026-10-02-vscode-settings-writer-design.md):
#
#   ASK ONCE, PER EDITOR. settings.json is a file people annotate by hand and
#   often sync between machines, so nothing is written until the user has said
#   yes for that editor. "Nobody was at the terminal to ask" is not a no, and is
#   not stored as one.
#
#   NO KEY WITHOUT A RECORD. The record of what an apply wrote is saved BEFORE
#   settings.json is written, and put back if the write fails. A crash can leave
#   a record naming keys that never landed -- a later reset finds them absent,
#   which is harmless -- and never a key in the user's file that no command can
#   name.
#
#   REFUSE RATHER THAN GUESS. An editor that cannot be identified, a settings
#   folder that does not exist, a file that does not parse and a state file
#   that cannot be read all stop the write and say which.

function Get-VSCodeStatePath {
    # Where the per-editor consent and undo records live. One file for every
    # editor, keyed by the variant names Get-VSCodeVariant returns.
    Join-Path $script:TStylesDataRoot 'vscode-state.json'
}

function ConvertTo-VSCodeRecord {
    <#
    .SYNOPSIS
    A record read back from JSON, rebuilt in the shape the apply produced.

    .DESCRIPTION
    ConvertFrom-Json hands back PSCustomObjects, and on Windows PowerShell 5.1 a
    one-element array can arrive as its bare element. Invoke-VSCodeStyleReset
    walks Path as an array of key names, so a Path that collapsed to a string
    would no longer be the path it was. Rebuilding every Path as a [string[]]
    here means the reset never sees the difference between a record that went
    through a file and one that did not.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Parsed)

    if ($null -eq $Parsed) { return $null }

    $wrote = [System.Collections.Generic.List[object]]::new()
    foreach ($w in @($Parsed.Wrote)) {
        if ($null -eq $w) { continue }
        $had = $null
        if ($null -ne $w.Had) { $had = [string]$w.Had }
        $wrote.Add(@{
            Path    = [string[]]@(@($w.Path) | ForEach-Object { [string]$_ })
            Literal = [string]$w.Literal
            Had     = $had
        })
    }

    $created = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($Parsed.CreatedParents)) {
        if ($null -eq $c) { continue }
        $created.Add([string[]]@(@($c) | ForEach-Object { [string]$_ }))
    }

    return @{
        Style          = [string]$Parsed.Style
        Wrote          = $wrote.ToArray()
        CreatedParents = $created.ToArray()
    }
}

function Read-VSCodeState {
    <#
    .SYNOPSIS
    The per-editor state: @{ Ok; Path; Entries }.

    .DESCRIPTION
    Entries maps a variant name to @{ consent; settingsPath; record }. consent
    is 'yes', 'no' or '' (never asked). A missing file is Ok with no entries --
    nothing has been asked or written yet.

    A file that exists and cannot be read is NOT Ok, and is not quietly treated
    as empty. It holds the only record of which keys TerminalStyles put into a
    settings.json; starting a fresh one would throw that away, and the keys
    with it. Callers refuse to write while it is in that state and say so.
    #>
    [CmdletBinding()]
    param()

    $path = Get-VSCodeStatePath
    $entries = @{}
    if (-not [System.IO.File]::Exists($path)) {
        return @{ Ok = $true; Path = $path; Entries = $entries }
    }

    try {
        $json = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
        if (-not $json.Trim()) { return @{ Ok = $true; Path = $path; Entries = $entries } }
        $obj = $json | ConvertFrom-Json -ErrorAction Stop
        if ($obj -isnot [System.Management.Automation.PSCustomObject]) {
            return @{ Ok = $false; Path = $path; Entries = @{} }
        }
        foreach ($p in $obj.PSObject.Properties) {
            $v = $p.Value
            $entries[$p.Name] = @{
                consent      = [string]$v.consent
                settingsPath = [string]$v.settingsPath
                record       = (ConvertTo-VSCodeRecord -Parsed $v.record)
            }
        }
    } catch {
        return @{ Ok = $false; Path = $path; Entries = @{} }
    }
    return @{ Ok = $true; Path = $path; Entries = $entries }
}

function Write-VSCodeState {
    # Throws on failure, on purpose: a caller about to touch settings.json has
    # to know its record did not land first. Through Write-SettingsAtomic, so a
    # crash mid-write leaves the old file or the new one, never half of either.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entries)

    $out = [ordered]@{}
    foreach ($name in @($Entries.Keys | Sort-Object)) {
        $e = $Entries[$name]
        $out[$name] = [ordered]@{
            consent      = $e.consent
            settingsPath = $e.settingsPath
            record       = $e.record
        }
    }
    Write-SettingsAtomic -Path (Get-VSCodeStatePath) -Json ($out | ConvertTo-Json -Depth 10)
}

function Set-VSCodeStateEntry {
    <#
    .SYNOPSIS
    Change one editor's entry, leaving every other editor's as it was.

    .DESCRIPTION
    Only what the caller BOUND changes: -Record $null clears a record, and an
    absent -Record leaves it alone. Throws when the state file cannot be read,
    for the reason Read-VSCodeState gives -- rewriting it would drop the other
    editors' records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Variant,
        [string]$SettingsPath,
        [ValidateSet('yes', 'no')][string]$Consent,
        [AllowNull()]$Record
    )

    $state = Read-VSCodeState
    if (-not $state.Ok) { throw "Could not read $($state.Path)" }

    $entry = $state.Entries[$Variant]
    if (-not $entry) { $entry = @{ consent = ''; settingsPath = ''; record = $null } }
    if ($PSBoundParameters.ContainsKey('SettingsPath')) { $entry.settingsPath = $SettingsPath }
    if ($PSBoundParameters.ContainsKey('Consent'))      { $entry.consent      = $Consent }
    if ($PSBoundParameters.ContainsKey('Record'))       { $entry.record       = $Record }
    $state.Entries[$Variant] = $entry
    Write-VSCodeState -Entries $state.Entries
}

function Resolve-VSCodeTarget {
    <#
    .SYNOPSIS
    Which editor this terminal belongs to, and its settings.json:
    @{ Status; Variant; Path }.

    .DESCRIPTION
    Status is 'ok', 'unknownvariant' or 'nodir'.

      unknownvariant  Get-VSCodeVariant could not name exactly one editor.
                      NEVER defaulted to 'Code': see that function for what
                      guessing cost.
      nodir           the editor's User folder does not exist. Nothing is
                      created -- an editor that has never run has nowhere it
                      would read a file from.

    A User folder with no settings.json in it is 'ok': VS Code creates the file
    the first time a setting changes, so writing the first one is what it would
    have done.

    -Variant skips detection, for callers that already know which editor they
    mean. The rest are test seams, forwarded by what was BOUND -- and a bound
    -HomeDir also suppresses the ambient APPDATA, the way Get-VSCodeSettingsPath
    has it suppress XDG_CONFIG_HOME, so a sandboxed test on Windows cannot
    resolve to the operator's own roaming profile.
    #>
    [CmdletBinding()]
    param(
        [string]$Variant,
        [string]$HomeDir,
        [string]$AppData,
        [string]$XdgConfigHome,
        [string]$AskpassNode,
        [string]$GitAskpass
    )

    if (-not $Variant) {
        $askSplat = @{}
        if ($PSBoundParameters.ContainsKey('AskpassNode')) { $askSplat.AskpassNode = $AskpassNode }
        if ($PSBoundParameters.ContainsKey('GitAskpass'))  { $askSplat.GitAskpass  = $GitAskpass }
        $Variant = Get-VSCodeVariant @askSplat
        if (-not $Variant) { return @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
    }

    $pathSplat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $pathSplat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('AppData')) {
        $pathSplat.AppData = $AppData
    } elseif ($PSBoundParameters.ContainsKey('HomeDir')) {
        $pathSplat.AppData = ''
    }
    if ($PSBoundParameters.ContainsKey('XdgConfigHome')) { $pathSplat.XdgConfigHome = $XdgConfigHome }

    $path = Get-VSCodeSettingsPath -Variant $Variant @pathSplat
    if (-not [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($path))) {
        return @{ Status = 'nodir'; Variant = $Variant; Path = $path }
    }
    return @{ Status = 'ok'; Variant = $Variant; Path = $path }
}

function Read-VSCodeSettingsText {
    # The file's text, or '' when there is no file yet. ReadAllText drops a
    # BOM; Write-SettingsAtomic puts it back, from the live file.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Test-VSCodeSettingsReadable {
    <#
    .SYNOPSIS
    Is this text something the JSONC editor can safely splice?

    .DESCRIPTION
    Blank is readable: it is what VS Code itself treats as "no settings yet".
    Otherwise the root must be an object, and that object must close.

    Asked BEFORE an apply or a reset rather than left to them, because the
    reset does not refuse broken text: on a file truncated mid-write it
    reported 'reset', removed 24 keys and kept one -- measured -- splicing
    against offsets that no longer meant what the record thought. Clearing the
    record after that would strand whatever it had not reached.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if (-not $Text.Trim()) { return $true }
    $tokens = Get-JsoncToken -Text $Text
    $open = Find-JsoncRootObject -Tokens $tokens
    if ($open -lt 0) { return $false }
    return ((Find-JsoncCloseBrace -Tokens $tokens -OpenIndex $open) -ge 0)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/Lib-Loading.Tests.ps1, tests/Splat-Variables-Defined.Tests.ps1 -Output Detailed"`
Expected: all PASS. `Lib-Loading` must see that the new file defines functions and parses, and the splat lint must accept `$askSplat` and `$pathSplat`.

- [ ] **Step 5: Commit**

```bash
git add lib/vscodewriter.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Add the VS Code state store and target resolution"
```

---

### Task 2: Consent, and the one answer to "is the writer on?"

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: Task 1, plus the existing `Test-InteractiveConsole` and `Confirm-Action -Question`.
- Produces:
  - `Get-VSCodeWriterState` → `@{ Status = 'active'|'declined'|'undecided'|'unknownvariant'|'nodir'|'statecorrupt'; Variant; Path; Entry }`.
  - `Test-VSCodeWriterActive` → `[bool]`.
  - `Request-VSCodeWriterConsent` → the writer status after asking. It asks only when the editor is `undecided` and a console is attached.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'Get-VSCodeWriterState and the question it asks' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-Host { }
        }

        It 'is undecided before anyone has been asked' {
            (Get-VSCodeWriterState).Status | Should -Be 'undecided'
            Test-VSCodeWriterActive | Should -BeFalse
        }

        It 'passes through an editor it cannot name' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Get-VSCodeWriterState).Status | Should -Be 'unknownvariant'
        }

        It 'passes through a missing settings folder' {
            Mock Resolve-VSCodeTarget { @{ Status = 'nodir'; Variant = 'Code'; Path = $script:sPath } }
            (Get-VSCodeWriterState).Status | Should -Be 'nodir'
        }

        It 'is statecorrupt when the record file cannot be read' {
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{broken', [System.Text.UTF8Encoding]::new($false))
            (Get-VSCodeWriterState).Status | Should -Be 'statecorrupt'
        }

        It 'asks at a console, remembers yes, and does not ask again' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Request-VSCodeWriterConsent | Should -Be 'active'
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            Request-VSCodeWriterConsent | Should -Be 'active'
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It -Because 'once per editor'
            Test-VSCodeWriterActive | Should -BeTrue
        }

        It 'remembers no' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $false }
            Request-VSCodeWriterConsent | Should -Be 'declined'
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'no'
            Request-VSCodeWriterConsent | Should -Be 'declined'
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'does not ask, and stores nothing, when nobody is at the console' {
            # Confirm-Action would answer $false here too -- for "nobody could be
            # asked", which must not be stored as the user's no.
            Mock Test-InteractiveConsole { $false }
            Mock Confirm-Action { throw 'nobody is there to be asked' }
            Request-VSCodeWriterConsent | Should -Be 'undecided'
            [System.IO.File]::Exists((Get-VSCodeStatePath)) | Should -BeFalse
        }

        It 'names the file it would write, in the question' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $false }
            Request-VSCodeWriterConsent | Out-Null
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match "Code's settings\.json" }
        }

        It 'reports an answer it could not store, and stays undecided' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Mock Set-VSCodeStateEntry { throw 'read-only' }
            Request-VSCodeWriterConsent | Should -Be 'undecided'
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Could not save that answer' }
        }

        It 'does not ask an editor that has already answered' {
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { throw 'already answered' }
            Request-VSCodeWriterConsent | Should -Be 'declined'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describe FAILS with `The term 'Get-VSCodeWriterState' is not recognized`. Task 1's tests still pass.

- [ ] **Step 3: Append the implementation to `lib/vscodewriter.ps1`**

```powershell

function Get-VSCodeWriterState {
    <#
    .SYNOPSIS
    Does a VS Code apply write settings.json right now, and if not, why not.

    .DESCRIPTION
    THE one answer. Get-TerminalCapability asks it (through
    Test-VSCodeWriterActive) to decide what VS Code claims, and the publisher
    asks it to decide whether to write -- so the "can't show" notice and the
    write cannot disagree about the same apply (CLAUDE.md: two implementations
    of one rule diverge).

    Returns @{ Status; Variant; Path; Entry }. Status is one of:
      active          identified editor, settings folder present, consent yes
      declined        consent no
      undecided       never asked, or nobody was there to answer
      unknownvariant  see Resolve-VSCodeTarget
      nodir           see Resolve-VSCodeTarget
      statecorrupt    vscode-state.json exists and cannot be read
    #>
    [CmdletBinding()]
    param()

    $t = Resolve-VSCodeTarget
    $out = @{ Status = $t.Status; Variant = $t.Variant; Path = $t.Path; Entry = $null }
    if ($t.Status -ne 'ok') { return $out }

    $state = Read-VSCodeState
    if (-not $state.Ok) { $out.Status = 'statecorrupt'; return $out }

    $entry = $state.Entries[$t.Variant]
    $out.Entry = $entry
    $consent = ''
    if ($entry) { $consent = $entry.consent }
    switch ($consent) {
        'yes'   { $out.Status = 'active' }
        'no'    { $out.Status = 'declined' }
        default { $out.Status = 'undecided' }
    }
    return $out
}

function Test-VSCodeWriterActive {
    # What Get-TerminalCapability's VSCode arm asks. A predicate over the one
    # decider above, not a second opinion.
    [CmdletBinding()]
    param()
    return ((Get-VSCodeWriterState).Status -eq 'active')
}

function Request-VSCodeWriterConsent {
    <#
    .SYNOPSIS
    Ask, once per editor, whether TerminalStyles may write its settings.json.
    Returns the writer status after asking (see Get-VSCodeWriterState).

    .DESCRIPTION
    Only an 'undecided' editor is asked, and only at a real console. The
    console check comes FIRST and is this function's own, not Confirm-Action's:
    that function answers $false both for "the user said no" and for "nobody
    could be asked", and storing the second as a no would turn the writer off
    for good the first time `tstyles eva` ran from a script.

    An answer that cannot be stored is reported, and the editor stays
    undecided: without a stored state the publisher could not save an undo
    record either, so honouring the yes for this run would only end in a
    failed write.
    #>
    [CmdletBinding()]
    param()

    $w = Get-VSCodeWriterState
    if ($w.Status -ne 'undecided') { return $w.Status }
    if (-not (Test-InteractiveConsole)) { return 'undecided' }

    Write-Host ""
    Write-Host ("  Save styles to {0}'s settings.json, so new terminals keep them?" -f $w.Variant)
    Write-Host "  This sets the terminal's colors, font and cursor there; tstyles reset" -ForegroundColor DarkGray
    Write-Host "  puts back whatever was there before. Change your mind any time with" -ForegroundColor DarkGray
    Write-Host "  tstyles vscode on  or  tstyles vscode off." -ForegroundColor DarkGray
    $answer = 'no'
    if (Confirm-Action -Question '  Save to settings.json? [y/N]') { $answer = 'yes' }

    try {
        Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Consent $answer
    } catch {
        Write-Host ("  Could not save that answer to {0}, so nothing is written to" -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        Write-Host "  settings.json this time, and you will be asked again." -ForegroundColor Yellow
        return 'undecided'
    }
    if ($answer -eq 'yes') { return 'active' }
    return 'declined'
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/vscodewriter.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Ask once per editor before writing VS Code's settings.json"
```

---

### Task 3: The publisher, and what it says

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes:
  - Tasks 1–2.
  - `Invoke-VSCodeStyleApply -Text -StyleDir -StyleName -PreviousRecord` → `@{ Text; Record; Changed; Status; Kept }`.
  - `Get-VSCodeColorOverride -Text -Ids`, which returns `,$arr`, so assign it and never wrap it in `@()`.
  - `Save-FirstTouchBackup -Path -Content` → the backup path or `$null`.
  - `Write-SettingsAtomic`.
- Produces:
  - `Publish-StyleVSCodeConfig -StyleName -StyleDir -Kind [-Session <hashtable>]` → `$null` off VS Code. Otherwise it returns:
    `@{ Status; Variant; Path; Kept = [string[]]; Replaced = [string[]]; Overrides = @(@{Scope;Ids}); Backup; FailedPath; Detail }`
    - Status: `written|declined|undecided|unknownvariant|nodir|statecorrupt|wontparse|writefailed`.
    - Kept and Replaced name keys as `'workbench.colorCustomizations/terminal.background'` or `'terminal.integrated.fontFamily'`.
    - A settings.json that exists but cannot be read is `wontparse` with Detail `'it could not be read'` (`Read-VSCodeSettingsText` throws on a failed read since Task 1's fix round), never `writefailed` and never treated as empty.
  - `Show-VSCodeWriteResult -Result` prints the result. It is a no-op on `$null` and prints a leading blank line.
- **Session contract,** used by Task 7. A session is a hashtable with at least `OnDiskRecord` and `Backup`. When `-Session` is passed, the publisher undoes by `$Session.OnDiskRecord` instead of the stored record, and reports `$Session.Backup`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'Publish-StyleVSCodeConfig' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            $script:eva      = Get-StyleDir -StyleName 'eva'

            # A style with a scheme and no theme.json: it writes colours only,
            # never a font or a cursor.
            $script:plain = Join-Path $script:TStylesDataRoot 'styles/plain'
            New-Item -ItemType Directory -Path $script:plain -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:plain 'scheme.json'),
                '{"name":"plain","background":"#101010","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))

            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
        }

        It 'returns nothing off VS Code' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'WezTerm' |
                Should -BeNullOrEmpty
        }

        It 'writes the style, keeps the comments, and saves the record' {
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            $text = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $text -Path @('workbench.colorCustomizations', 'terminal.background') |
                Should -Not -BeNullOrEmpty
            Test-JsoncCommentsIntact -Before $script:user -After $text | Should -BeTrue
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'
        }

        It 'takes a first-touch copy before the first write, and only then' {
            $r1 = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r1.Backup | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($r1.Backup) | Should -BeExactly $script:user
            $r2 = Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode'
            $r2.Backup | Should -BeNullOrEmpty -Because 'a later copy would capture a file that already carries a style'
        }

        It 'writes nothing while <consent>' -ForEach @(
            @{ consent = 'declined';  expected = 'declined' }
            @{ consent = 'undecided'; expected = 'undecided' }
        ) {
            if ($consent -eq 'declined') {
                Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            } else {
                Remove-Item -LiteralPath (Get-VSCodeStatePath) -Force
            }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be $expected
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'passes an editor it cannot name straight through, reading nothing' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            Mock Read-VSCodeSettingsText { throw 'must not read' }
            (Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode').Status |
                Should -Be 'unknownvariant'
        }

        It 'refuses a file that does not parse, and keeps no record' {
            [System.IO.File]::WriteAllText($script:sPath, '{ "a": 1 ', [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'does not parse'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly '{ "a": 1 '
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'refuses a file it cannot read, rather than treating it as empty' {
            # Held open with no sharing: ReadAllText fails on every platform
            # the suite runs on. Writing over it would replace the user's file.
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            } finally { $fs.Dispose() }
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'could not be read'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'says what is wrong when the colour block is not an object' {
            [System.IO.File]::WriteAllText($script:sPath, '{ "workbench.colorCustomizations": null }',
                [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'colorCustomizations'
        }

        It 'starts a missing settings.json from {}' {
            Remove-Item -LiteralPath $script:sPath -Force
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            Test-VSCodeSettingsReadable -Text ([System.IO.File]::ReadAllText($script:sPath)) | Should -BeTrue
            $r.Backup | Should -BeNullOrEmpty -Because 'there was no file to copy'
        }

        It 'puts the record back when the settings write fails' {
            # Pester 6 throws on a call no filter matches (Pester 5 called the
            # real command), so the state write needs a default mock to land on.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status     | Should -Be 'writefailed'
            $r.FailedPath | Should -Be $script:sPath
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty -Because 'no key landed, so no record may claim one'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'does not touch settings.json when its record cannot be saved' {
            Mock Set-VSCodeStateEntry { throw 'read-only data root' }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status     | Should -Be 'writefailed'
            $r.FailedPath | Should -Be (Get-VSCodeStatePath)
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'names a theme block that will hide the colours' {
            $scoped = "{`n  `"workbench.colorCustomizations`": {`n    `"[Monokai]`": { `"terminal.background`": `"#000000`" }`n  }`n}"
            [System.IO.File]::WriteAllText($script:sPath, $scoped, [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            @($r.Overrides).Count | Should -Be 1
            $r.Overrides[0].Scope | Should -Be '[Monokai]'
            $r.Overrides[0].Ids   | Should -Contain 'terminal.background'
        }

        It 'says which hand edits it left, and which the next style wrote over' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            # Two keys changed by hand while koholint is on: one the next style
            # also sets (the background), one it does not (the font).
            $t = [System.IO.File]::ReadAllText($script:sPath)
            $t = (Set-JsoncLiteral -Text $t -Path @('workbench.colorCustomizations', 'terminal.background') -Literal '"#000000"').Text
            $t = (Set-JsoncLiteral -Text $t -Path @('terminal.integrated.fontFamily') -Literal '"Mine Mono"').Text
            [System.IO.File]::WriteAllText($script:sPath, $t, [System.Text.UTF8Encoding]::new($false))

            $r = Publish-StyleVSCodeConfig -StyleName 'plain' -StyleDir $script:plain -Kind 'VSCode'
            $r.Status   | Should -Be 'written'
            $r.Replaced | Should -Contain 'workbench.colorCustomizations/terminal.background'
            $r.Kept     | Should -Contain 'terminal.integrated.fontFamily'
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) -Path @('terminal.integrated.fontFamily') |
                Should -Be '"Mine Mono"'
        }
    }
}

Describe 'Show-VSCodeWriteResult' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Write-Host { }
            $script:base = @{
                Variant = 'Code'; Path = '/x/Code/User/settings.json'; Kept = @(); Replaced = @()
                Overrides = @(); Backup = $null; FailedPath = '/x/Code/User/settings.json'
                Detail = 'it does not parse as a JSON object'
            }
        }

        It 'says <status> in its own words' -ForEach @(
            @{ status = 'written';        pattern = "Saved to Code's settings\.json" }
            @{ status = 'declined';       pattern = 'tstyles vscode on' }
            @{ status = 'undecided';      pattern = 'no answer on record' }
            @{ status = 'unknownvariant'; pattern = "Couldn't tell which editor" }
            @{ status = 'nodir';          pattern = 'no settings folder' }
            @{ status = 'wontparse';      pattern = 'does not parse' }
            @{ status = 'writefailed';    pattern = 'Could not write' }
            @{ status = 'statecorrupt';   pattern = 'Could not read' }
        ) {
            $r = $script:base.Clone(); $r.Status = $status
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match $pattern }
        }

        It 'never says Saved unless it was written' {
            foreach ($s in 'declined', 'undecided', 'unknownvariant', 'nodir', 'wontparse', 'writefailed', 'statecorrupt') {
                $r = $script:base.Clone(); $r.Status = $s
                Show-VSCodeWriteResult -Result $r
            }
            # -cmatch: -match is case-insensitive, and 'Not saved to' contains 'saved to'.
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -cmatch '\bSaved to' }
        }

        It 'names kept and replaced keys, and an overriding theme block' {
            $r = $script:base.Clone(); $r.Status = 'written'
            $r.Kept = @('terminal.integrated.fontFamily')
            $r.Replaced = @('workbench.colorCustomizations/terminal.background')
            $r.Overrides = @(@{ Scope = '[Monokai]'; Ids = @('terminal.background') })
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Left terminal\.integrated\.fontFamily' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Replaced workbench\.colorCustomizations/terminal\.background' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match '\[Monokai\]' }
        }

        It 'prints nothing for no result' {
            Show-VSCodeWriteResult -Result $null
            Should -Invoke Write-Host -Times 0 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the two new Describes FAIL with `The term 'Publish-StyleVSCodeConfig' is not recognized` / `'Show-VSCodeWriteResult'`.

- [ ] **Step 3: Append the implementation to `lib/vscodewriter.ps1`**

```powershell

function Publish-StyleVSCodeConfig {
    <#
    .SYNOPSIS
    Write a style into this editor's settings.json, with its undo record.
    Returns a result for Show-VSCodeWriteResult, or $null off VS Code.

    .DESCRIPTION
    The fourth config writer's door, beside Publish-StyleWezTermConfig and
    called from the same places: Apply-StyleNonWT, and the picker's Enter.
    It never asks -- callers ask first, so the "can't show" notice printed
    before it already reflects the answer -- and it never prints: the picker
    computes it above a Clear-Host and shows it below one.

    -Session is the picker's preview session. While the picker runs, the file
    holds a PREVIEW, described by the session's record rather than the stored
    one; undoing it by the stored record would miss the preview's keys and
    take them for the user's own edits.

    Kept is split in two on the way out. The apply's Kept names keys the
    outgoing style's undo left alone because the user had changed them; the
    incoming style then writes over any of those it sets itself, keeping the
    user's value as the one a reset restores. "Left as you set it" is only
    true of the others.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][hashtable]$Session
    )

    if ($Kind -ne 'VSCode') { return $null }

    $w = Get-VSCodeWriterState
    $result = @{
        Status = $w.Status; Variant = $w.Variant; Path = $w.Path
        Kept = @(); Replaced = @(); Overrides = @()
        Backup = $null; FailedPath = $null; Detail = $null
    }
    if ($w.Status -ne 'active') { return $result }

    $stored = $null
    if ($w.Entry) { $stored = $w.Entry.record }
    $onDisk = $stored
    if ($Session) {
        $onDisk = $Session.OnDiskRecord
        $result.Backup = $Session.Backup
    }

    try {
        $text = Read-VSCodeSettingsText -Path $w.Path
    } catch {
        # Refused, not guessed: a file that exists and cannot be read is not
        # "no settings yet", and writing over it would replace it outright.
        $result.Status = 'wontparse'; $result.Detail = 'it could not be read'
        return $result
    }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) {
        $result.Status = 'wontparse'; $result.Detail = 'it does not parse as a JSON object'
        return $result
    }

    # VS Code's own empty settings file is "{}"; a blank or missing one means
    # the same, and is the one case a reset does not return byte for byte --
    # it leaves "{}", which VS Code reads identically.
    $base = $text
    if (-not $base.Trim()) { $base = '{}' }

    $a = Invoke-VSCodeStyleApply -Text $base -StyleDir $StyleDir -StyleName $StyleName -PreviousRecord $onDisk
    if ($a.Status -ne 'applied') {
        $result.Status = 'wontparse'
        $result.Detail = switch ($a.Status) {
            'parentnotobject' { 'workbench.colorCustomizations in it is not an object' }
            default           { 'it does not parse as a JSON object' }
        }
        return $result
    }

    # FIRST touch: only while none of our keys are in the file. A copy taken
    # later would capture a file that already carries a style (CLAUDE.md,
    # "Encoding and culture, on files the user owns").
    if (-not $onDisk -and $text -and -not $result.Backup) {
        $result.Backup = Save-FirstTouchBackup -Path $w.Path -Content $text
    }

    try {
        Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $a.Record
    } catch {
        $result.Status = 'writefailed'; $result.FailedPath = (Get-VSCodeStatePath)
        return $result
    }

    if ($a.Text -cne $text) {
        try {
            Write-SettingsAtomic -Path $w.Path -Json $a.Text
        } catch {
            $result.Status = 'writefailed'; $result.FailedPath = $w.Path
            try {
                Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $stored
            } catch {
                # Both writes failed. The record now describes keys that never
                # landed, and the keys still in the file are named by no record --
                # say so, rather than let a later reset leave them without a word.
                $result.Detail = 'its undo record could not be restored either'
            }
            return $result
        }
    }

    $writtenNames = @(@($a.Record.Wrote) | ForEach-Object { @($_.Path) -join '/' })
    $kept = @($a.Kept)
    $ids = @(@($a.Record.Wrote) |
             Where-Object { @($_.Path).Count -eq 2 -and $_.Path[0] -eq 'workbench.colorCustomizations' } |
             ForEach-Object { $_.Path[1] })
    # Assigned, not wrapped: Get-VSCodeColorOverride returns ,$arr.
    $overrides = Get-VSCodeColorOverride -Text $a.Text -Ids $ids

    $result.Status    = 'written'
    $result.Kept      = @($kept | Where-Object { $writtenNames -notcontains $_ })
    $result.Replaced  = @($kept | Where-Object { $writtenNames -contains $_ })
    $result.Overrides = $overrides
    return $result
}

function Show-VSCodeWriteResult {
    <#
    .SYNOPSIS
    Say what Publish-StyleVSCodeConfig did, in the words for that outcome.

    .DESCRIPTION
    One arm per status and no shared "success" line: "Saved" is printed on the
    written path and nowhere else (CLAUDE.md: every message is a claim, and a
    status is not a boolean). Leading blank line, no trailing one -- the
    callers own their spacing, as with Show-UnsupportedStyleField.
    #>
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    Write-Host ""
    switch ($Result.Status) {
        'written' {
            Write-Host ("  Saved to {0}'s settings.json -- new terminals keep it." -f $Result.Variant) -ForegroundColor DarkGray
            if ($Result.Backup) {
                Write-Host ("  The file as it was before is kept at {0}" -f $Result.Backup) -ForegroundColor DarkGray
            }
            foreach ($k in @($Result.Kept)) {
                Write-Host ("  Left {0} as you set it (you changed it after the last style wrote it)." -f $k) -ForegroundColor DarkGray
            }
            foreach ($k in @($Result.Replaced)) {
                Write-Host ("  Replaced {0}, which you had changed by hand; tstyles reset puts yours back." -f $k) -ForegroundColor DarkGray
            }
            foreach ($o in @($Result.Overrides)) {
                Write-Host ("  {0} in workbench.colorCustomizations also sets {1}," -f $o.Scope, (@($o.Ids) -join ', ')) -ForegroundColor Yellow
                Write-Host "  and wins over this style while that color theme is active." -ForegroundColor Yellow
            }
        }
        'declined' {
            Write-Host ("  Not saved to {0}'s settings.json, as you chose. tstyles vscode on changes that." -f $Result.Variant) -ForegroundColor DarkGray
        }
        'undecided' {
            Write-Host ("  Not saved to {0}'s settings.json: there is no answer on record for it yet." -f $Result.Variant) -ForegroundColor DarkGray
            Write-Host "  tstyles vscode on gives one." -ForegroundColor DarkGray
        }
        'unknownvariant' {
            Write-Host "  Couldn't tell which editor this terminal belongs to, so nothing was saved" -ForegroundColor Yellow
            Write-Host "  -- the colors apply to this terminal only." -ForegroundColor Yellow
        }
        'nodir' {
            Write-Host ("  Found no settings folder for {0} at {1}, so nothing was saved." -f
                        $Result.Variant, [System.IO.Path]::GetDirectoryName($Result.Path)) -ForegroundColor Yellow
        }
        'wontparse' {
            Write-Host ("  Could not edit {0} safely: {1}." -f $Result.Path, $Result.Detail) -ForegroundColor Yellow
            Write-Host "  Nothing was written to it. Fix the file and apply the style again." -ForegroundColor Yellow
        }
        'writefailed' {
            Write-Host ("  Could not write {0}." -f $Result.FailedPath) -ForegroundColor Yellow
            Write-Host "  This terminal keeps the colors; new terminals won't." -ForegroundColor Yellow
            if ($Result.Detail) {
                Write-Host ("  And {0}, so a reset may leave some of the previous style's settings in place." -f $Result.Detail) -ForegroundColor Yellow
            }
        }
        'statecorrupt' {
            Write-Host ("  Could not read {0}, which records what tstyles wrote to settings.json." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host "  Nothing was written. Fix that file: deleting it lets tstyles write again, but loses" -ForegroundColor Yellow
            Write-Host "  its record of any style already in settings.json." -ForegroundColor Yellow
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/vscodewriter.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Write a style into VS Code's settings.json, record first"
```

---

### Task 4: The reset, and what it says

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: Tasks 1–3, plus `Invoke-VSCodeStyleReset -Text -Record` → `@{ Text; Restored; Removed; Kept; Status }`.
- Produces:
  - `Reset-StyleVSCodeConfig [-Variant]` → `@{ Status = 'reset'|'norecord'|'unknownvariant'|'statecorrupt'|'wontparse'|'writefailed'; Variant; Path; Kept; Restored; Removed; Detail }`. Detail says why for `wontparse`: `'it could not be read'` or `'it does not parse as a JSON object'`. It works from the **recorded** settings path. Without `-Variant` it detects the editor.
  - `Show-VSCodeResetResult -Result` prints the result, prints nothing for `norecord` or `$null`, and has no leading blank line.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'Reset-StyleVSCodeConfig' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'

            function script:Publish([string]$Name) {
                Publish-StyleVSCodeConfig -StyleName $Name -StyleDir (Get-StyleDir -StyleName $Name) -Kind 'VSCode' | Out-Null
            }
        }

        It 'puts the file back byte for byte, and clears the record' {
            script:Publish 'koholint'
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'still does, after a chain of styles' {
            script:Publish 'koholint'; script:Publish 'eva'; script:Publish 'sober'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'leaves a key you changed since, and names it' {
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $t -Path @('terminal.integrated.fontFamily') -Literal '"Mine Mono"').Text,
                [System.Text.UTF8Encoding]::new($false))
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Kept | Should -Contain 'terminal.integrated.fontFamily'
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) -Path @('terminal.integrated.fontFamily') |
                Should -Be '"Mine Mono"'
        }

        It 'says norecord, and touches nothing, when no style was saved' {
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:sPath)
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'norecord'
            [System.IO.File]::GetLastWriteTimeUtc($script:sPath) | Should -Be $stamp
        }

        It 'keeps the record when the file no longer parses' {
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath, $t.Substring(0, $t.Length - 3), [System.Text.UTF8Encoding]::new($false))
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'wontparse'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty -Because 'a later reset still needs it'
        }

        It 'keeps the record when the file cannot be read' {
            script:Publish 'koholint'
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                $r = Reset-StyleVSCodeConfig -Variant 'Code'
            } finally { $fs.Dispose() }
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'could not be read'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty
        }

        It 'keeps the record when the write fails' {
            script:Publish 'koholint'
            # Pester 6 throws on a call no filter matches (Pester 5 called the
            # real command), so the state write needs a default mock to land on.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'writefailed'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty
        }

        It 'works from any terminal, off the recorded path' {
            script:Publish 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'refuses to guess when it has to find the editor itself' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Reset-StyleVSCodeConfig).Status | Should -Be 'unknownvariant'
        }

        It 'does not bring back a settings.json deleted since' {
            script:Publish 'koholint'
            Remove-Item -LiteralPath $script:sPath -Force
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::Exists($script:sPath) | Should -BeFalse
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        # Review Focus 1-3.
        It 'returns a CRLF file with its CRLF' {
            $crlf = "{`r`n  // mine`r`n  `"editor.fontSize`": 13`r`n}"
            [System.IO.File]::WriteAllText($script:sPath, $crlf, [System.Text.UTF8Encoding]::new($false))
            script:Publish 'koholint'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $crlf
        }

        It 'keeps a byte-order mark through apply and reset' {
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($true))
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath))
            script:Publish 'koholint'
            $mid = [System.IO.File]::ReadAllBytes($script:sPath)
            ($mid[0] -eq 0xEF -and $mid[1] -eq 0xBB -and $mid[2] -eq 0xBF) | Should -BeTrue -Because 'the apply keeps the BOM'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath)) | Should -BeExactly $before
        }

        It 'still takes everything out after the file was re-indented' {
            # VS Code's settings UI and Settings Sync both rewrite the file.
            # What the reset compares is each value's text, not its position.
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath, ($t -replace "`n  ", "`n    "), [System.Text.UTF8Encoding]::new($false))
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            @($r.Kept).Count | Should -Be 0 -Because 'no value changed, only the whitespace around it'
            $after = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $after -Path @('workbench.colorCustomizations') | Should -BeNullOrEmpty
            Get-JsoncValueLiteral -Text $after -Path @('terminal.integrated.fontFamily') | Should -BeNullOrEmpty
            Get-JsoncValueLiteral -Text $after -Path @('editor.fontSize') | Should -Be '13'
        }
    }
}

Describe 'Show-VSCodeResetResult' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host { } }

        It 'says <status> in its own words' -ForEach @(
            @{ status = 'reset';          pattern = "Took the style back out of Code's settings\.json" }
            @{ status = 'unknownvariant'; pattern = "Couldn't tell which editor" }
            @{ status = 'statecorrupt';   pattern = 'Could not read' }
            @{ status = 'wontparse';      pattern = 'Could not edit .* safely: it could not be read' }
            @{ status = 'writefailed';    pattern = 'Could not write' }
        ) {
            Show-VSCodeResetResult -Result @{ Status = $status; Variant = 'Code'; Path = '/x/settings.json'
                                              Kept = @(); Restored = @(); Removed = @(); Detail = 'it could not be read' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match $pattern }
        }

        It 'stays quiet when there was nothing of ours to take out' {
            Show-VSCodeResetResult -Result @{ Status = 'norecord'; Variant = 'Code'; Path = $null
                                              Kept = @(); Restored = @(); Removed = @() }
            Should -Invoke Write-Host -Times 0 -Scope It
        }

        It 'names a key it left' {
            Show-VSCodeResetResult -Result @{ Status = 'reset'; Variant = 'Code'; Path = '/x'
                                              Kept = @('terminal.integrated.fontFamily'); Restored = @(); Removed = @() }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Left terminal\.integrated\.fontFamily' }
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describes FAIL with `The term 'Reset-StyleVSCodeConfig' is not recognized`.

- [ ] **Step 3: Append the implementation to `lib/vscodewriter.ps1`**

```powershell

function Reset-StyleVSCodeConfig {
    <#
    .SYNOPSIS
    Take a style back out of one editor's settings.json, by its record.

    .DESCRIPTION
    The record says what to undo, and Invoke-VSCodeStyleReset decides per key:
    restored, removed, or kept because the user changed it since. The record
    is cleared only AFTER the file is written: clearing it first and then
    failing the write would leave keys in the file that no command could name.

    -Variant names the editor; omitted, it is the one this terminal belongs
    to. Works off the RECORDED settings path, so uninstall and `tstyles vscode
    off` can run it from any terminal.

    Returns @{ Status; Variant; Path; Kept; Restored; Removed; Detail }, Status
    one of reset, norecord, unknownvariant, statecorrupt, wontparse,
    writefailed. Detail says why for wontparse: the file could not be read, or
    does not parse.
    #>
    [CmdletBinding()]
    param([string]$Variant)

    $result = @{ Status = 'norecord'; Variant = $Variant; Path = $null; Kept = @(); Restored = @(); Removed = @(); Detail = $null }

    if (-not $Variant) {
        $t = Resolve-VSCodeTarget
        if (-not $t.Variant) { $result.Status = 'unknownvariant'; return $result }
        $Variant = $t.Variant
        $result.Variant = $Variant
    }

    $state = Read-VSCodeState
    if (-not $state.Ok) { $result.Status = 'statecorrupt'; return $result }
    $entry = $state.Entries[$Variant]
    if (-not $entry -or -not $entry.record) { return $result }
    $result.Path = $entry.settingsPath

    try {
        $text = Read-VSCodeSettingsText -Path $entry.settingsPath
    } catch {
        $result.Status = 'wontparse'; $result.Detail = 'it could not be read'
        return $result
    }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) {
        $result.Status = 'wontparse'; $result.Detail = 'it does not parse as a JSON object'
        return $result
    }

    $r = Invoke-VSCodeStyleReset -Text $text -Record $entry.record
    if ($r.Text -cne $text) {
        try {
            Write-SettingsAtomic -Path $entry.settingsPath -Json $r.Text
        } catch {
            $result.Status = 'writefailed'
            return $result
        }
    }
    try {
        Set-VSCodeStateEntry -Variant $Variant -Record $null
    } catch {
        # The file is clean, but the record still names the style's values, so
        # the next reset or apply would take the user's own settings for hand
        # edits. Say so rather than leave it to be misread later.
        $result.Detail = 'its record could not be cleared'
    }

    $result.Status   = 'reset'
    $result.Kept     = @($r.Kept)
    $result.Restored = @($r.Restored)
    $result.Removed  = @($r.Removed)
    return $result
}

function Show-VSCodeResetResult {
    # Say what Reset-StyleVSCodeConfig did. Quiet on 'norecord': nothing of
    # ours was there, and saying so on every reset in every VS Code terminal
    # would be noise. No leading blank line: it is printed inside other
    # commands' blocks (reset, uninstall, `tstyles vscode off`).
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    switch ($Result.Status) {
        'reset' {
            Write-Host ("  Took the style back out of {0}'s settings.json." -f $Result.Variant) -ForegroundColor DarkGray
            foreach ($k in @($Result.Kept)) {
                Write-Host ("  Left {0} as you set it (you changed it after the style wrote it)." -f $k) -ForegroundColor DarkGray
            }
            if ($Result.Detail) {
                Write-Host ("  But {0}, so the next apply or reset may wrongly call some of your settings hand edits." -f $Result.Detail) -ForegroundColor Yellow
            }
        }
        'unknownvariant' {
            Write-Host "  Couldn't tell which editor this terminal belongs to, so no settings.json" -ForegroundColor Yellow
            Write-Host "  was touched." -ForegroundColor Yellow
        }
        'statecorrupt' {
            Write-Host ("  Could not read {0}, which records what tstyles wrote to settings.json," -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host "  so nothing was taken out of it. Fix that file and reset again -- deleting it would" -ForegroundColor Yellow
            Write-Host "  leave the style in settings.json with no record to take it out by." -ForegroundColor Yellow
        }
        'wontparse' {
            Write-Host ("  Could not edit {0} safely: {1}, so the style was left in it." -f $Result.Path, $Result.Detail) -ForegroundColor Yellow
            Write-Host "  Fix the file and reset again -- the record of what to take out is kept." -ForegroundColor Yellow
        }
        'writefailed' {
            Write-Host ("  Could not write {0}, so the style is still in it." -f $Result.Path) -ForegroundColor Yellow
            Write-Host "  The record of what to take out is kept; reset again once it can be written." -ForegroundColor Yellow
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: all PASS. If the CRLF, BOM or re-indent test fails, **stop and report**. Do not loosen the assertion: it means `lib/jsonctext.ps1` does not round-trip that input, and fixing that is a separate decision for the maintainer.

- [ ] **Step 5: Commit**

```bash
git add lib/vscodewriter.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Take a style back out of VS Code's settings.json by its record"
```

---

### Task 5: Claim the font and cursor only while the writer is on

**Files:**
- Modify: `terminals.ps1` (the VSCode arm of `Get-TerminalCapability`, `Get-UnsupportedStyleField`, and the `Persist` comment)
- Modify: `lib/fonts.ps1` (the style-owned post-install lines in `Invoke-TerminalStyleFont`)
- Modify: `tests/Get-TerminalCapability.Tests.ps1`, `tests/Font-ApplyPromise.Tests.ps1`
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: `Test-VSCodeWriterActive` (Task 2) and `Get-VSCodeCursorStyle` (existing).
- Produces: `Get-TerminalCapability -Kind 'VSCode'` claims `Persist`, `Font` and `CursorShape` only while `Test-VSCodeWriterActive` is true. It claims `OscPalette` always, and nothing else ever.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'what VS Code claims, and the notice that reads it' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Get-StyleBundledBackground { $null }
            $script:theme = [pscustomobject]@{
                font = [pscustomobject]@{ face = 'Cascadia Code'; size = 11 }; cursorShape = 'bar'
            }
        }

        It 'names font and cursor shape while the writer is off' {
            Mock Test-VSCodeWriterActive { $false }
            $f = Get-UnsupportedStyleField -Theme $script:theme -StyleDir $TestDrive -Kind 'VSCode'
            $f | Should -Contain 'font'
            $f | Should -Contain 'cursor shape'
        }

        It 'names neither once it is on' {
            Mock Test-VSCodeWriterActive { $true }
            $f = @(Get-UnsupportedStyleField -Theme $script:theme -StyleDir $TestDrive -Kind 'VSCode')
            $f | Should -Not -Contain 'font'
            $f | Should -Not -Contain 'cursor shape'
        }

        It 'still names a cursor shape VS Code has no answer for' {
            Mock Test-VSCodeWriterActive { $true }
            $odd = [pscustomobject]@{ cursorShape = 'doubleUnderscore' }
            Get-UnsupportedStyleField -Theme $odd -StyleDir $TestDrive -Kind 'VSCode' | Should -Contain 'cursor shape'
        }

        It 'never claims what settings.json cannot carry, even when on' {
            Mock Test-VSCodeWriterActive { $true }
            $caps = Get-TerminalCapability -Kind 'VSCode'
            $caps.Persist     | Should -BeTrue
            $caps.Font        | Should -BeTrue
            $caps.CursorShape | Should -BeTrue
            foreach ($n in 'Opacity', 'BackgroundImage', 'Padding', 'TabColor', 'TabTitle') {
                $caps[$n] | Should -BeFalse -Because "VS Code has no setting that delivers $n"
            }
        }
    }
}

Describe 'tstyles font in a VS Code terminal' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:cat = @([pscustomobject]@{
                name = 'JetBrains Mono'; family = 'JetBrains Mono'; license = 'OFL-1.1'
                url = 'https://example.invalid/x.zip'; sha256 = 'deadbeef' })
            Mock Get-FontCatalog     { $script:cat }
            Mock Test-FontInstalled  { $true }
            Mock Find-WTSettingsPath { $null }
            Mock Get-TerminalKind    { 'VSCode' }
        }

        It 'says the style owns the font once the writer is on, and gives no WezTerm advice' {
            Mock Test-VSCodeWriterActive { $true }
            Get-FontOwner -Kind 'VSCode' | Should -Be 'style'
            $out = Invoke-TerminalStyleFont -Name 'JetBrains Mono' 6>&1 | Out-String
            $out | Should -Match 'tstyles tune'
            $out | Should -Not -Match 'config\.font' -Because 'that route exists on WezTerm only'
        }

        It 'leaves the font to VS Code while the writer is off' {
            Mock Test-VSCodeWriterActive { $false }
            Get-FontOwner -Kind 'VSCode' | Should -Be 'terminal'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: FAIL on 'names neither once it is on' (font is still named), 'never claims what settings.json cannot carry' (Persist false) and 'says the style owns the font' (owner is `terminal`).

- [ ] **Step 3: Change the VSCode capability arm in `terminals.ps1`**

Replace:

```powershell
        'VSCode' {
            # The integrated terminal honours OSC colors for the session but its
            # settings live in VS Code's own settings.json, which is not ours to
            # rewrite. Live-only.
            $caps.OscPalette = $true
        }
```

with:

```powershell
        'VSCode' {
            # The integrated terminal honours OSC colors for the session, and
            # lib/vscodewriter.ps1 writes the rest into the editor's own
            # settings.json -- but only for an editor it can identify, whose
            # owner has said yes (asked once; see Request-VSCodeWriterConsent).
            # So the claim is CONDITIONAL, and Test-VSCodeWriterActive is the
            # same answer the writer itself acts on: the "can't show" notice and
            # the write cannot disagree about one apply.
            #
            # Font and CursorShape are terminal.integrated.fontFamily/fontSize/
            # fontWeight and terminal.integrated.cursorStyle. Opacity, Padding,
            # TabColor, TabTitle and BackgroundImage have no VS Code setting --
            # terminal.background is a solid colour -- so they stay off and
            # stay named.
            $caps.OscPalette = $true
            if (Test-VSCodeWriterActive) {
                $caps.Persist     = $true
                $caps.Font        = $true
                $caps.CursorShape = $true
            }
        }
```

- [ ] **Step 4: Name an unmappable cursor shape in `Get-UnsupportedStyleField` (`terminals.ps1`)**

Replace:

```powershell
    if ((& $declares 'cursorShape') -and -not $caps.CursorShape) { $unsupported += 'cursor shape' }
```

with:

```powershell
    if ((& $declares 'cursorShape') -and -not $caps.CursorShape) {
        $unsupported += 'cursor shape'
    } elseif ($Kind -eq 'VSCode' -and (& $declares 'cursorShape') -and
              -not (Get-VSCodeCursorStyle -CursorShape "$($Theme.cursorShape)")) {
        # VS Code takes three shapes, and Get-VSCodeStylePlan writes nothing for
        # one it cannot map -- so the flag being on does not cover THIS style's
        # cursor.
        $unsupported += 'cursor shape'
    }
```

- [ ] **Step 5: Update the `Persist` comment in `terminals.ps1`**

Replace the whole line

```powershell
    # .terminal profile, and WezTerm's generated Lua module. Not to be confused with a style surviving a new tab,
```

with these two lines:

```powershell
    # .terminal profile, WezTerm's generated Lua module, and -- once its owner
    # has said yes -- a VS Code-family editor's settings.json. Not to be confused with a style surviving a new tab,
```

The line before it (`# where a writer exists: Windows Terminal's settings.json, Terminal.app's`) stays as it is.

- [ ] **Step 6: Scope the `config.font` advice to WezTerm (`lib/fonts.ps1`)**

Replace:

```powershell
            Write-Host "  To use it: tstyles tune <style> and save, which keeps the font with the style --" -ForegroundColor DarkGray
            Write-Host "  or set config.font AFTER the terminalstyles require line in your own config." -ForegroundColor DarkGray
```

with:

```powershell
            Write-Host "  To use it: tstyles tune <style> and save, which keeps the font with the style." -ForegroundColor DarkGray
            # The second route is WezTerm's alone. In VS Code the style's font is
            # a key in settings.json, and the next apply writes over a hand edit
            # there (keeping it as the value a reset puts back), so there is no
            # "set it after" that sticks.
            if ($fontKind -eq 'WezTerm') {
                Write-Host "  Or set config.font AFTER the terminalstyles require line in your own config." -ForegroundColor DarkGray
            }
```

- [ ] **Step 7: Pin the developer's own state out of two existing test files**

These files call `Get-TerminalCapability -Kind 'VSCode'` unmocked. Inside a VS Code terminal whose owner has said yes, they would read that real state. CI is unaffected, but a local run would fail.

In `tests/Get-TerminalCapability.Tests.ps1`:

1. Replace

   ```powershell
           $script:AllKinds = @('WindowsTerminal','AppleTerminal','ITerm2','Ghostty',
   ```

   with

   ```powershell
           # VS Code's flags depend on whether its writer is on for the editor
           # this runs in. Off by default here, so the developer's own answer
           # cannot decide these tests; the on-state has its own test below.
           BeforeAll { Mock Test-VSCodeWriterActive { $false } }

           $script:AllKinds = @('WindowsTerminal','AppleTerminal','ITerm2','Ghostty',
   ```

2. Replace the three comment lines

   ```powershell
               # THREE writers now: Merge-StyleIntoSettings (Windows Terminal's
               # settings.json), New-AppleTerminalProfile (Terminal.app's .terminal
               # plist) and Get-WezTermStyleLua (WezTerm's generated Lua module).
   ```

   with

   ```powershell
               # FOUR writers now: Merge-StyleIntoSettings (Windows Terminal's
               # settings.json), New-AppleTerminalProfile (Terminal.app's .terminal
               # plist), Get-WezTermStyleLua (WezTerm's generated Lua module) and
               # Invoke-VSCodeStyleApply (VS Code's settings.json, written once the
               # user has said yes -- see the conditional test below).
   ```

3. Replace `$writers = @('WindowsTerminal', 'AppleTerminal', 'WezTerm')` with `$writers = @('WindowsTerminal', 'AppleTerminal', 'WezTerm', 'VSCode')`.

4. In the `$writerFor` map, after `WezTerm         = 'Get-WezTermStyleLua'`, add the line `VSCode          = 'Invoke-VSCodeStyleApply'`.

5. After the `'every terminal on that writer list really has a writer'` It block, add:

   ```powershell
           It 'claims VS Code''s stored visuals only while its writer is on' {
               Mock Test-VSCodeWriterActive { $true }
               $on = Get-TerminalCapability -Kind 'VSCode'
               $on.Persist     | Should -BeTrue
               $on.Font        | Should -BeTrue
               $on.CursorShape | Should -BeTrue

               Mock Test-VSCodeWriterActive { $false }
               $off = Get-TerminalCapability -Kind 'VSCode'
               foreach ($n in ($script:TStylesCapabilityNames | Where-Object { $_ -ne 'OscPalette' })) {
                   $off[$n] | Should -BeFalse -Because "with the writer off nothing delivers $n"
               }
           }
   ```

In `tests/Font-ApplyPromise.Tests.ps1`, replace

```powershell
Describe 'the font messages name whoever really decides the font' {
    InModuleScope TerminalStyles {

        It 'gives three answers, because there are three' {
```

with

```powershell
Describe 'the font messages name whoever really decides the font' {
    InModuleScope TerminalStyles {
        # VS Code's answer depends on whether its writer is on here; pinned off
        # so the developer's own state cannot decide it. The on-state is tested
        # in VSCode-Writer.Tests.ps1.
        BeforeAll { Mock Test-VSCodeWriterActive { $false } }

        It 'gives three answers, because there are three' {
```

- [ ] **Step 8: Run the affected tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/Get-TerminalCapability.Tests.ps1, tests/Font-ApplyPromise.Tests.ps1, tests/Get-UnsupportedStyleField.Tests.ps1, tests/Get-PickerCapabilityNote.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add terminals.ps1 lib/fonts.ps1 tests/VSCode-Writer.Tests.ps1 tests/Get-TerminalCapability.Tests.ps1 tests/Font-ApplyPromise.Tests.ps1
git commit -m "Claim VS Code's font and cursor only while its writer is on"
```

---

### Task 6: `tstyles <name>` and `tstyles reset` reach the writer

**Files:**
- Modify: `lib/applystyle.ps1` (`Apply-StyleNonWT`, `Reset-StyleNonWT`)
- Modify: `lib/help.ps1` (the `reset` topic's Detail)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: `Request-VSCodeWriterConsent`, `Publish-StyleVSCodeConfig`, `Show-VSCodeWriteResult`, `Reset-StyleVSCodeConfig`, `Show-VSCodeResetResult`.
- Produces: no new functions. Behaviour: on `Kind -eq 'VSCode'`, `Apply-StyleNonWT` asks **before** building the "can't show" notice, then publishes and shows the result. `Reset-StyleNonWT` resets this editor. `random`, `tune` save and `delete` all reach `Apply-StyleDirect` / `Reset-StyleDirect`, which hand off here, so they need no change.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'tstyles <name> and tstyles reset in a VS Code terminal' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'

            Mock Get-TerminalKind { 'VSCode' }
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-HostOscPacket { $true }
            Mock Get-StyleBundledBackground { $null }
            Mock Write-Host { }
        }

        It 'asks once, and asks before the notice is built' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) `
                -Path @('workbench.colorCustomizations', 'terminal.background') | Should -Not -BeNullOrEmpty
            # Had the question come after the notice, the notice would have
            # named the font this very apply then wrote.
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match "can't show:.*\bfont\b" }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'says Saved, once' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Should -Invoke Write-Host -Times 1 -Exactly -Scope It -ParameterFilter { "$Object" -match "Saved to Code's settings\.json" }
        }

        It 'writes nothing, and says why, when nobody is there to ask' {
            Mock Test-InteractiveConsole { $false }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'no answer on record' }
        }

        It 'tstyles reset takes it back out, byte for byte' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Reset-StyleNonWT -OutputRedirected $false
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match "Took the style back out of Code's settings\.json" }
        }

        It 'a reset in another terminal leaves VS Code alone' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            $styled = [System.IO.File]::ReadAllText($script:sPath)
            Mock Get-TerminalKind { 'AppleTerminal' }
            Reset-StyleNonWT -OutputRedirected $false
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $styled
        }

        It 'the reset help no longer says there is no settings file off Windows Terminal' {
            $reset = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'reset' })
            ($reset.Detail -join ' ') | Should -Match 'VS Code'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describe FAILS. Nothing is written, Confirm-Action is never invoked, and the reset help does not mention VS Code.

- [ ] **Step 3: Ask first in `Apply-StyleNonWT` (`lib/applystyle.ps1`)**

Replace:

```powershell
    # local was how the notice ended up deciding for itself which two fields
    # mattered.
    $kind = Get-TerminalKind
```

with:

```powershell
    # local was how the notice ended up deciding for itself which two fields
    # mattered.
    $kind = Get-TerminalKind

    # VS Code: ask (once per editor) whether its settings.json may be written,
    # BEFORE anything below reads the capability table. The "can't show"
    # notice is built from it, and has to reflect the answer.
    if ($kind -eq 'VSCode') { [void](Request-VSCodeWriterConsent) }
```

- [ ] **Step 4: Publish beside WezTerm in `Apply-StyleNonWT`**

Replace:

```powershell
    Publish-StyleWezTermConfig -StyleName $StyleName -StyleDir $StyleDir `
        -Scheme $scheme -Theme $theme -Kind $kind | Out-Null
    Write-Host ""
```

with:

```powershell
    Publish-StyleWezTermConfig -StyleName $StyleName -StyleDir $StyleDir `
        -Scheme $scheme -Theme $theme -Kind $kind | Out-Null
    # The fourth writer, called beside the third for the reason the picker's
    # confirm gives: every publisher the direct path calls, the picker calls.
    Show-VSCodeWriteResult -Result (Publish-StyleVSCodeConfig -StyleName $StyleName -StyleDir $StyleDir -Kind $kind)
    Write-Host ""
```

- [ ] **Step 5: Reset VS Code in `Reset-StyleNonWT`**

First, replace the head comment line

```powershell
    # Nothing was written to a settings file, so there is nothing to strip --
```

with

```powershell
    # Nothing was written to a settings file -- VS Code's aside, which keeps a
    # record of what it wrote and is undone from it below -- so there is nothing to strip --
```

Then replace:

```powershell
    # True on all three paths: the loader target is removed either way.
    Write-Host "  Open a new tab to restore your default prompt."
```

with:

```powershell
    # VS Code's settings.json, when a style was saved there. From its record,
    # so it does not matter whether the style still exists.
    if ($kind -eq 'VSCode') {
        Show-VSCodeResetResult -Result (Reset-StyleVSCodeConfig)
    }
    # True on all three paths: the loader target is removed either way.
    Write-Host "  Open a new tab to restore your default prompt."
```

- [ ] **Step 6: Make the `reset` help topic true (`lib/help.ps1`)**

Replace:

```powershell
                       "On Windows Terminal that means editing settings.json, and a",
                       "settings.json.bak is written first. Elsewhere there is no",
                       "settings.json to strip: the reset is an escape sequence handing",
                       "color control back to the terminal's own profile, so there is",
                       "nothing to back up and no .bak is written.",
```

with:

```powershell
                       "On Windows Terminal that means editing settings.json, and a",
                       "settings.json.bak is written first. In a VS Code terminal, a",
                       "style that was saved to the editor's own settings.json is taken",
                       "back out of it, from the record kept when it was written: your",
                       "earlier values come back, and any you changed since are left",
                       "alone and named. Elsewhere there is no settings file to strip:",
                       "the reset is an escape sequence handing color control back to",
                       "the terminal's own profile, so there is nothing to back up and",
                       "no .bak is written.",
```

- [ ] **Step 7: Run the affected tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/Apply-StyleNonWT.Tests.ps1, tests/Reset-StyleDirect.Tests.ps1, tests/Show-TerminalStyleHelp.Tests.ps1, tests/WezTerm-Writer.Tests.ps1 -Output Detailed"`
Expected: all PASS. `Show-TerminalStyleHelp`'s "reset topic does not promise a backup that only Windows Terminal gets" still passes, because the Detail still contains "Elsewhere".

- [ ] **Step 8: Commit**

```bash
git add lib/applystyle.ps1 lib/help.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Write and reset VS Code's settings.json from tstyles <name> and reset"
```

---

### Task 7: The picker's preview session

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `New-VSCodePreviewSession` → `$null` when the writer is off (it asks first if the editor is undecided). Otherwise a session hashtable:
    `@{ Variant; Path; OriginalText; OriginalExisted; StartRecord; OnDiskRecord; LastWrittenText; Cache; BackedUp; Backup }`.
  - `Invoke-VSCodePreview -Session -StyleName -StyleDir` → `'written'|'current'|'changed'|'wontparse'|'failed'`. Every preview is computed from `OriginalText` with `-PreviousRecord StartRecord`, cached per style name, and never touches the state file. `changed` means the file no longer holds what the session last left in it, because somebody edited it, so no preview is written over that edit.
  - `Restore-VSCodePreview -Session` → `@{ Status = 'none'|'restored'|'merged'|'failed'; Path; Kept; Replaced; Reason; Detail }`. It never throws, and after a success a second call returns `none`. `Kept` and `Replaced` split the same way the publisher's do (spec revision 5). `Detail` is set only on `failed`, when the preview's record could not be saved either.
  - `Show-VSCodeRestoreResult -Result` prints for `merged` and `failed` only.
  - `Publish-StyleVSCodeConfig -Session` from Task 3 already commits a session.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'the picker''s VS Code preview session' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            $script:eva      = Get-StyleDir -StyleName 'eva'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-Host { }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
        }

        It 'is $null while the writer is off, so the picker stays colors-only' {
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            New-VSCodePreviewSession | Should -BeNullOrEmpty
        }

        It 'gives no session for a file it cannot read, so nothing is previewed over it' {
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                New-VSCodePreviewSession | Should -BeNullOrEmpty
            } finally { $fs.Dispose() }
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'asks first when nobody has been asked' {
            Remove-Item -LiteralPath (Get-VSCodeStatePath) -Force
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            New-VSCodePreviewSession | Should -Not -BeNullOrEmpty
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'previews from the original every time, never from the last preview' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
        }

        It 'leaves the saved record alone while it previews' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty -Because 'a preview is not an apply'
        }

        It 'Esc puts the exact bytes back, BOM included' {
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($true))
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath))
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath)) | Should -BeExactly $before
        }

        It 'Esc removes a settings.json the picker created' {
            Remove-Item -LiteralPath $script:sPath -Force
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            [System.IO.File]::Exists($script:sPath) | Should -BeTrue
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            [System.IO.File]::Exists($script:sPath) | Should -BeFalse
        }

        # Review Focus 5.
        It 'Esc with nothing previewed writes nothing' {
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:sPath)
            $s = New-VSCodePreviewSession
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none'
            [System.IO.File]::GetLastWriteTimeUtc($script:sPath) | Should -Be $stamp
        }

        It 'a second Esc finds nothing to do' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none'
        }

        It 'Esc after an edit keeps the edit and puts the starting style back' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $start = [System.IO.File]::ReadAllText($script:sPath)
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null

            # Somebody edits settings.json in VS Code while the picker is open.
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('editor.fontSize') -Literal '15').Text,
                [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'merged'
            $text = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $text -Path @('editor.fontSize') | Should -Be '15' -Because 'the edit is theirs'
            # eva writes fontWeight 600 and koholint "normal": which one is in
            # the file says which style came back.
            Get-JsoncValueLiteral -Text $text -Path @('terminal.integrated.fontWeight') |
                Should -Be (Get-JsoncValueLiteral -Text $start -Path @('terminal.integrated.fontWeight'))
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'

            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Set-JsoncLiteral -Text $script:user -Path @('editor.fontSize') -Literal '15').Text
        }

        It 'Esc names a key the starting style sets again as replaced, not left' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null

            # The edit is to a key both styles write (eva 600, koholint "normal").
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('terminal.integrated.fontWeight') -Literal '"bold"').Text,
                [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'merged'
            @($r.Replaced) | Should -Contain 'terminal.integrated.fontWeight'
            @($r.Kept) | Should -Not -Contain 'terminal.integrated.fontWeight'
        }

        It 'Esc will not undo into a file that no longer parses, and keeps the preview''s record' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null

            # Saved half-way through an edit: the root object never closes.
            $broken = ([System.IO.File]::ReadAllText($script:sPath)).TrimEnd().TrimEnd('}')
            [System.IO.File]::WriteAllText($script:sPath, $broken, [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match 'no longer parses'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $broken
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the preview is what the file still holds'
        }

        It 'Esc that cannot write keeps the preview''s record, so reset can take it out' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            # Pester 6 throws on a call no filter matches, so the default mock
            # lets the state file's own write through.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match 'locked'
            $r.Detail | Should -BeNullOrEmpty
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'
        }

        It 'Esc says so when the preview''s record cannot be saved either' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            Mock Write-SettingsAtomic { throw 'locked' }

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -Be 'its undo record could not be saved either'
        }

        It 'stops previewing into a file somebody else changed, and Esc keeps the edit' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'

            # Somebody edits settings.json in VS Code while the picker is open.
            $edited = (Set-JsoncLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) `
                           -Path @('editor.fontSize') -Literal '15').Text
            [System.IO.File]::WriteAllText($script:sPath, $edited, [System.Text.UTF8Encoding]::new($false))

            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'changed'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $edited

            (Restore-VSCodePreview -Session $s).Status | Should -Be 'merged'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Set-JsoncLiteral -Text $script:user -Path @('editor.fontSize') -Literal '15').Text
        }

        It 'Enter commits what is on disk, with a record that undoes it to the original' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null
            $r = Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s
            $r.Status | Should -Be 'written'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        # Review Focus 5.
        It 'Enter with nothing previewed is a plain apply' {
            $s = New-VSCodePreviewSession
            Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
        }

        It 'reports the first-touch copy it took during the preview' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' -Session $s
            $r.Backup | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($r.Backup) | Should -BeExactly $script:user
        }
    }
}

Describe 'Show-VSCodeRestoreResult' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host { } }

        It 'says the edit survived when it merged' {
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Your edit is still there' }
        }

        It 'names a key the starting style set again, and does not call that edit still there' {
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x'; Kept = @(); Replaced = @('terminal.integrated.fontWeight'); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Replaced terminal\.integrated\.fontWeight' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Your edit is still there' }
        }

        It 'says how to get out when it failed' {
            Show-VSCodeRestoreResult -Result @{ Status = 'failed'; Path = '/x'; Kept = @(); Replaced = @(); Reason = 'locked'; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'tstyles reset takes it out' }
        }

        It 'does not promise a reset that has no record to work from' {
            Show-VSCodeRestoreResult -Result @{ Status = 'failed'; Path = '/x'; Kept = @(); Replaced = @(); Reason = 'locked'; Detail = 'its undo record could not be saved either' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'tstyles reset cannot take it out' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'tstyles reset takes it out' }
        }

        It 'stays quiet for <status>' -ForEach @(@{ status = 'none' }, @{ status = 'restored' }) {
            Show-VSCodeRestoreResult -Result @{ Status = $status; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Times 0 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describes FAIL with `The term 'New-VSCodePreviewSession' is not recognized`.

- [ ] **Step 3: Append the implementation to `lib/vscodewriter.ps1`**

```powershell

function New-VSCodePreviewSession {
    <#
    .SYNOPSIS
    The picker's VS Code state for one run, or $null when it previews colours
    only.

    .DESCRIPTION
    The picker's body needs a console and a keypress loop no test can drive,
    so everything VS Code does in it lives here, as data a test can hold:
    the file's exact original text, the record of the style that was on when
    the picker opened, and the record of whatever preview is on disk now.

    Asks first (once per editor) when nobody has answered -- the picker calls
    this below its console guard, so there is someone to ask. $null when the
    writer is off, or when the file does not parse: previews would refuse
    anyway, and Enter reports the reason through the publisher.
    #>
    [CmdletBinding()]
    param()

    if ((Request-VSCodeWriterConsent) -ne 'active') { return $null }
    $w = Get-VSCodeWriterState
    if ($w.Status -ne 'active') { return $null }

    $existed = [System.IO.File]::Exists($w.Path)
    # A file that cannot be read gets no session: there would be nothing exact
    # to put back on Esc, and a preview written over it would replace it. Enter
    # still reaches the publisher, which says why it wrote nothing.
    try { $text = Read-VSCodeSettingsText -Path $w.Path } catch { return $null }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) { return $null }

    $start = $null
    if ($w.Entry) { $start = $w.Entry.record }
    return @{
        Variant         = $w.Variant
        Path            = $w.Path
        OriginalText    = $text
        OriginalExisted = $existed
        StartRecord     = $start
        OnDiskRecord    = $start
        LastWrittenText = $null
        Cache           = @{}
        BackedUp        = $false
        Backup          = $null
    }
}

function Invoke-VSCodePreview {
    <#
    .SYNOPSIS
    Put one style's preview into settings.json. Returns written, current,
    changed, wontparse or failed.

    .DESCRIPTION
    Always computed from the ORIGINAL text, undoing the style that was on when
    the picker opened -- never from the previous preview, so previews cannot
    build on each other. Cached per style: one apply costs 0.2-1.3 s depending
    on the file (measured), and arrowing back to a style should not pay twice.

    The state file is not touched. A preview is not an apply; Enter is, and
    Esc must find the stored record exactly as the picker found it.

    'changed': the file no longer holds what the session last left in it, so
    somebody else wrote it while the picker was open. Nothing is written over
    that edit. Esc and Enter both start from the file as it is now, so both
    keep the edit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir
    )

    if (-not $Session.Cache.ContainsKey($StyleName)) {
        $base = $Session.OriginalText
        if (-not $base.Trim()) { $base = '{}' }
        $a = Invoke-VSCodeStyleApply -Text $base -StyleDir $StyleDir -StyleName $StyleName -PreviousRecord $Session.StartRecord
        if ($a.Status -ne 'applied') { return 'wontparse' }
        $Session.Cache[$StyleName] = @{ Text = $a.Text; Record = $a.Record }
    }
    $p = $Session.Cache[$StyleName]

    $onDiskText = $Session.OriginalText
    if ($null -ne $Session.LastWrittenText) { $onDiskText = $Session.LastWrittenText }
    if ($p.Text -ceq $onDiskText) {
        $Session.OnDiskRecord = $p.Record
        return 'current'
    }

    try {
        # VS Code's settings UI, Settings Sync or a hand edit can write the
        # file while the picker is open. A preview computed from the original
        # would throw that edit away.
        if ((Read-VSCodeSettingsText -Path $Session.Path) -cne $onDiskText) { return 'changed' }
        if (-not $Session.BackedUp) {
            if (-not $Session.StartRecord -and $Session.OriginalExisted -and $Session.OriginalText) {
                $Session.Backup = Save-FirstTouchBackup -Path $Session.Path -Content $Session.OriginalText
            }
            $Session.BackedUp = $true
        }
        Write-SettingsAtomic -Path $Session.Path -Json $p.Text
    } catch {
        return 'failed'
    }
    $Session.LastWrittenText = $p.Text
    $Session.OnDiskRecord = $p.Record
    return 'written'
}

function Restore-VSCodePreview {
    <#
    .SYNOPSIS
    Esc, Ctrl+C or an error in the picker: take the preview back out.
    Returns @{ Status; Path; Kept; Replaced; Reason; Detail }, Status none,
    restored, merged or failed. Never throws.

    .DESCRIPTION
    Two cases, decided by whether the file still holds what the picker last
    wrote.

      It does    -> the original text goes back, byte for byte -- or the file
                    goes away again, if there was none.
      It doesn't -> somebody edited settings.json while the picker was open,
                    most likely in VS Code itself. Writing the original back
                    would throw that edit away. Instead the preview is undone
                    by its own record, which leaves the edit standing, and the
                    style that was on before is put back over it. Kept and
                    Replaced split the way the publisher's do: when the
                    starting style sets a key the user edited, that key is
                    replaced, and the edited value is what a reset restores.

    A file that no longer parses is not undone at all. The record's offsets no
    longer mean what the record thinks, so this fails rather than splices.

    On failure the stored record is set to the preview's, because the preview
    is what the file still holds: `tstyles reset` can then take it out. If
    that record cannot be saved either, Detail says so, and the message does
    not promise the reset.

    After either success nothing is left written, so a second call returns
    'none' -- which is what the picker's finally needs after an Esc.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Session)

    $out = @{ Status = 'none'; Path = $Session.Path; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
    if ($null -eq $Session.LastWrittenText) { return $out }

    try {
        $now = Read-VSCodeSettingsText -Path $Session.Path
        if ($now -ceq $Session.LastWrittenText) {
            if ($Session.OriginalExisted) {
                Write-SettingsAtomic -Path $Session.Path -Json $Session.OriginalText
            } elseif ([System.IO.File]::Exists($Session.Path)) {
                Remove-Item -LiteralPath $Session.Path -Force -ErrorAction Stop
            }
            $Session.OnDiskRecord = $Session.StartRecord
            $out.Status = 'restored'
        } else {
            if (-not (Test-VSCodeSettingsReadable -Text $now)) {
                throw 'it changed while the picker was open and no longer parses as a JSON object'
            }
            $undo = Invoke-VSCodeStyleReset -Text $now -Record $Session.OnDiskRecord
            $text = $undo.Text
            $record = $null
            $startStyle = $null
            if ($Session.StartRecord) { $startStyle = $Session.StartRecord.Style }
            if ($startStyle) {
                $startDir = Get-StyleDir -StyleName $startStyle
                if ($startDir) {
                    $re = Invoke-VSCodeStyleApply -Text $text -StyleDir $startDir -StyleName $startStyle
                    if ($re.Status -eq 'applied') { $text = $re.Text; $record = $re.Record }
                }
            }
            # Record first, as everywhere in this file.
            Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $record
            Write-SettingsAtomic -Path $Session.Path -Json $text
            $Session.OnDiskRecord = $record
            $rewritten = @()
            if ($record) { $rewritten = @(@($record.Wrote) | ForEach-Object { @($_.Path) -join '/' }) }
            $out.Status   = 'merged'
            $out.Kept     = @(@($undo.Kept) | Where-Object { $rewritten -notcontains $_ })
            $out.Replaced = @(@($undo.Kept) | Where-Object { $rewritten -contains $_ })
        }
        $Session.LastWrittenText = $null
    } catch {
        # Reason first, before the try below can replace $_.
        $out.Status = 'failed'
        $out.Reason = "$_"
        try {
            Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.OnDiskRecord
        } catch {
            $out.Detail = 'its undo record could not be saved either'
        }
    }
    return $out
}

function Show-VSCodeRestoreResult {
    # What the picker's Esc did to settings.json, when that is worth a line:
    # quiet for 'none' and 'restored', which are the file exactly as it was.
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    # Filtered, not just wrapped: @() around a missing member is one $null,
    # which would print a line naming nothing.
    $replaced = @($Result.Replaced | Where-Object { $_ })
    $kept     = @($Result.Kept | Where-Object { $_ })
    switch ($Result.Status) {
        'merged' {
            Write-Host ""
            Write-Host "  settings.json changed while the picker was open, so the preview was taken" -ForegroundColor Yellow
            Write-Host "  back out of it instead of the file being put back as it was." -ForegroundColor Yellow
            if ($replaced.Count -eq 0) {
                Write-Host "  Your edit is still there." -ForegroundColor Yellow
            } else {
                Write-Host "  What you changed is still there, except where the style you started with" -ForegroundColor Yellow
                Write-Host "  sets a key again:" -ForegroundColor Yellow
                foreach ($k in $replaced) {
                    Write-Host ("  Replaced {0}, which you had changed by hand; tstyles reset puts yours back." -f $k) -ForegroundColor DarkGray
                }
            }
            foreach ($k in $kept) {
                Write-Host ("  Left {0} as you set it." -f $k) -ForegroundColor DarkGray
            }
        }
        'failed' {
            Write-Host ""
            Write-Host ("  Could not put {0} back: {1}" -f $Result.Path, $Result.Reason) -ForegroundColor Red
            if ($Result.Detail) {
                Write-Host ("  The preview is still in it, and {0}, so tstyles reset cannot take it out." -f $Result.Detail) -ForegroundColor Red
            } else {
                Write-Host "  The preview is still in it; tstyles reset takes it out." -ForegroundColor Red
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/vscodewriter.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Preview VS Code styles from a session that can put the file back"
```

---

### Task 8: Wire the session into the picker

**Files:**
- Modify: `tstyles.ps1` (inside `Invoke-TerminalStyle`, picker section)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: `New-VSCodePreviewSession`, `Invoke-VSCodePreview`, `Restore-VSCodePreview`, `Show-VSCodeRestoreResult`, `Publish-StyleVSCodeConfig -Session`, `Show-VSCodeWriteResult`.
- Produces: no functions. The picker previews, reverts and commits through the session, and shows results below the `Clear-Host` that would wipe them. An error after Enter that skips the commit takes the preview back out, in the `finally`.

- [ ] **Step 1: Write the failing tests**

The picker body cannot be driven: it needs a console and a key loop. `tests/WezTerm-LivePreview.Tests.ps1` pins its wiring structurally for that reason, and the *behaviour* is pinned in Task 7. Append:

```powershell
Describe 'the picker wires the VS Code session in' {
    InModuleScope TerminalStyles {
        BeforeAll { $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() }

        It 'previews beside WezTerm, on the branch with no settings.json of its own' {
            $script:picker | Should -Match '& \$previewWezTerm \$i\s+& \$previewVSCode \$i'
        }

        It 'reverts through the one revert block Esc and the finally share' {
            $script:picker | Should -Match '(?s)\$restoreOriginalLook = \{\s*& \$restoreOriginalSettings\s*& \$restoreWezTerm\s*& \$restoreVSCode'
        }

        It 'opens the session below the console guard, so nobody is asked into a pipe' {
            $guard = $script:picker.IndexOf('The style picker needs an interactive terminal')
            $open  = $script:picker.IndexOf('$vscodeSession = New-VSCodePreviewSession')
            $guard | Should -BeGreaterThan 0
            $open  | Should -BeGreaterThan $guard
        }

        It 'commits with the session, and shows the result below the Clear-Host' {
            $publish = $script:picker.IndexOf('Publish-StyleVSCodeConfig')
            $publish | Should -BeGreaterThan 0
            $script:picker | Should -Match '-Session \$vscodeSession'
            $clear = $script:picker.IndexOf('Clear-Host', $publish)
            $show  = $script:picker.IndexOf('Show-VSCodeWriteResult -Result $vscodeResult')
            $clear | Should -BeGreaterThan $publish
            $show  | Should -BeGreaterThan $clear
        }

        It 'says what Esc did after it says Reverted' {
            $script:picker | Should -Match '(?s)Write-Host "Reverted\." -ForegroundColor Yellow\s*Show-VSCodeRestoreResult'
        }

        It 'takes the preview back out when an error after Enter skips the commit' {
            $publish = $script:picker.IndexOf('$vscodeResult = Publish-StyleVSCodeConfig')
            $done    = $script:picker.IndexOf('$pickerState.VSCodeDone = $true')
            $publish | Should -BeGreaterThan 0
            $done | Should -BeGreaterThan $publish -Because 'the session is settled only once the commit has run'
            $script:picker | Should -Match '(?s)if \(\$confirmed -and \$vscodeSession -and -not \$pickerState\.VSCodeDone\) \{\s*\$pickerState\.VSCodeRestore = Restore-VSCodePreview -Session \$vscodeSession'
        }

        # The six above pin WHERE the wiring sits. These four pin lines whose loss
        # changes what is left on disk, each found by deleting that line in a copy
        # of the picker and watching the six stay green. Text pins, like the six:
        # what the session does is pinned in the preview-session tests above.
        It 'puts the file back when the commit did not land' {
            $script:picker | Should -Match '(?s)if \(\$vscodeSession -and \$vscodeResult -and \$vscodeResult\.Status -ne ''written''\) \{[^}]*Restore-VSCodePreview -Session \$vscodeSession' `
                -Because 'a failed commit leaves the preview in the file while Publish rolls the stored record back; only this Restore puts the two back in agreement'
        }

        It 'commits through the session, so the preview is undone by its own record' {
            $script:picker | Should -Match '(?s)\$vscodeResult = Publish-StyleVSCodeConfig[^{]*?-Session \$vscodeSession' `
                -Because 'without the session the publisher undoes the style that was on when the picker opened, not the preview on disk, and a later reset leaves the preview in the file'
        }

        It 'says what putting the file back did, below the commit result' {
            $script:picker | Should -Match '(?s)Show-VSCodeWriteResult -Result \$vscodeResult\s*Show-VSCodeRestoreResult -Result \$pickerState\.VSCodeRestore' `
                -Because 'when the commit failed after a preview, what putting the file back did is told right after the commit result, below the Clear-Host'
        }

        It 'says what Ctrl+C put back' {
            $script:picker | Should -Match '(?s)try \{ & \$restoreOriginalLook \} catch \{ \}\s*Show-VSCodeRestoreResult' `
                -Because 'Ctrl+C and errors leave through the finally, which would otherwise say nothing about a merged or failed restore'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the ten new tests FAIL. Everything else passes.

- [ ] **Step 3: Add the picker state flag**

Replace `    $pickerState = @{ Reverted = $false; SettingsWritten = $false; WezWritten = $false }` with:

```powershell
    $pickerState = @{ Reverted = $false; SettingsWritten = $false; WezWritten = $false; VSCodeRestore = $null; VSCodeDone = $false }
```

- [ ] **Step 4: Add the VS Code preview and restore blocks before `$restoreOriginalSettings`**

Replace:

```powershell
    $restoreOriginalSettings = {
        if ($pickerState.SettingsWritten) {
```

with:

```powershell
    # VS Code: the same full preview, through the session vscodewriter.ps1
    # owns -- the picker body cannot be driven by a test, so the logic lives
    # where one can reach it. Opened below the console guard; $null until then,
    # and $null for good when the writer is off, which both blocks no-op on.
    $vscodeSession = $null
    $previewVSCode = {
        param([int]$i)
        if (-not $vscodeSession) { return }
        try {
            [void](Invoke-VSCodePreview -Session $vscodeSession -StyleName $styles[$i].Name `
                                        -StyleDir $styles[$i].FullName)
        } catch {
            # Same bargain as the WezTerm preview above: a preview that cannot
            # be written is not worth taking the picker down for, and the OSC
            # retint has already carried the colours.
        }
    }
    $restoreVSCode = {
        if (-not $vscodeSession) { return }
        $vr = Restore-VSCodePreview -Session $vscodeSession
        if ($vr.Status -ne 'none') { $pickerState.VSCodeRestore = $vr }
    }

    $restoreOriginalSettings = {
        if ($pickerState.SettingsWritten) {
```

- [ ] **Step 5: Open the session below the console guard**

Replace:

```powershell
        catch { $backupNote = Get-BackupFailureNote -Reason "$_" -InFrame }
    }

    [Console]::CursorVisible = $false
```

with:

```powershell
        catch { $backupNote = Get-BackupFailureNote -Reason "$_" -InFrame }
    }

    # VS Code: ask (once per editor) before the menu takes the screen, and keep
    # the exact text every preview starts from. Below the console guard, so the
    # question is never put to a pipe.
    if ($termKind -eq 'VSCode') { $vscodeSession = New-VSCodePreviewSession }

    [Console]::CursorVisible = $false
```

- [ ] **Step 6: Preview it**

Replace:

```powershell
                & $previewWezTerm $i
                if ($canPreviewTitle -and $titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
                return
```

with:

```powershell
                & $previewWezTerm $i
                & $previewVSCode $i
                if ($canPreviewTitle -and $titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
                return
```

- [ ] **Step 7: Revert it**

Replace:

```powershell
        $restoreOriginalLook = {
            & $restoreOriginalSettings
            & $restoreWezTerm
```

with:

```powershell
        $restoreOriginalLook = {
            & $restoreOriginalSettings
            & $restoreWezTerm
            & $restoreVSCode
```

- [ ] **Step 8: Say what Esc did**

Replace:

```powershell
        if ($result.Outcome -eq 'cancelled') {
            Clear-Host
            Write-Host "Reverted." -ForegroundColor Yellow
```

with:

```powershell
        if ($result.Outcome -eq 'cancelled') {
            Clear-Host
            Write-Host "Reverted." -ForegroundColor Yellow
            Show-VSCodeRestoreResult -Result $pickerState.VSCodeRestore
```

- [ ] **Step 9: Declare the confirm result next to the other confirm-time values**

Replace:

```powershell
        $unsupportedFields = @()
        if ($useSettingsFile) {
            $isPwshTarget = $false
```

with:

```powershell
        $unsupportedFields = @()
        # What Enter did to VS Code's settings.json. Computed with the other
        # publishers, shown below the Clear-Host for the reason above.
        $vscodeResult = $null
        if ($useSettingsFile) {
            $isPwshTarget = $false
```

- [ ] **Step 10: Commit it beside the WezTerm publisher**

Replace:

```powershell
            Publish-StyleWezTermConfig -StyleName $selectedStyle.Name `
                                       -StyleDir $selectedStyle.FullName `
                                       -Scheme $schemes[$idx] `
                                       -Theme $wtTheme -Kind $termKind | Out-Null
```

with:

```powershell
            Publish-StyleWezTermConfig -StyleName $selectedStyle.Name `
                                       -StyleDir $selectedStyle.FullName `
                                       -Scheme $schemes[$idx] `
                                       -Theme $wtTheme -Kind $termKind | Out-Null

            # ...and VS Code's settings.json, the fourth writer. With the
            # session, so the commit undoes the PREVIEW on disk rather than the
            # style that was on when the picker opened.
            $vscodeResult = Publish-StyleVSCodeConfig -StyleName $selectedStyle.Name `
                                -StyleDir $selectedStyle.FullName -Kind $termKind `
                                -Session $vscodeSession
            if ($vscodeSession -and $vscodeResult -and $vscodeResult.Status -ne 'written') {
                # The commit did not land, but a preview may have. Put the file
                # back rather than leave a style in it that no record describes.
                $pickerState.VSCodeRestore = Restore-VSCodePreview -Session $vscodeSession
            }
            # Settled either way from here: the finally must not take back a
            # commit that landed.
            $pickerState.VSCodeDone = $true
```

- [ ] **Step 11: Show it below the Clear-Host**

Replace:

```powershell
        if (@($unsupportedFields).Count -gt 0) {
            Show-UnsupportedStyleField -Field $unsupportedFields -Kind $termKind
            Write-Host ""
        }
```

with:

```powershell
        if (@($unsupportedFields).Count -gt 0) {
            Show-UnsupportedStyleField -Field $unsupportedFields -Kind $termKind
            Write-Host ""
        }

        # VS Code's settings.json: what Enter did to it, or why not -- and, if
        # the commit failed after a preview, what putting the file back did.
        if ($vscodeResult) {
            Show-VSCodeWriteResult -Result $vscodeResult
            Show-VSCodeRestoreResult -Result $pickerState.VSCodeRestore
            Write-Host ""
        }
```

- [ ] **Step 12: Say it on the Ctrl+C path too**

Replace:

```powershell
            if (-not $pickerState.Reverted -and $restoreOriginalLook) {
                try { & $restoreOriginalLook } catch { }
            }
```

with:

```powershell
            if (-not $pickerState.Reverted -and $restoreOriginalLook) {
                try { & $restoreOriginalLook } catch { }
                Show-VSCodeRestoreResult -Result $pickerState.VSCodeRestore
            }
```

- [ ] **Step 12b: Take the preview back out when an error skips the commit**

Enter sets `$confirmed` before the commit runs, and the `finally` reverts only while `$confirmed` is false. An exception in between, from `Set-CurrentStyleRecord`, `Set-ShellStyleState` or anything else on the confirm path, would leave the preview in `settings.json` with no record naming it. The spec's Esc / Ctrl+C / exception flow says to restore on an exception.

Replace:

```powershell
        # Clean up the background prefetch job. If it's still mid-fetch (user
```

with:

```powershell
        # Enter sets $confirmed before the VS Code commit runs, so an error in
        # between skips both the Esc revert and the block above, and would leave
        # the preview in settings.json with no record naming it. Restore never
        # throws, and VSCodeDone keeps it away from a commit that landed.
        if ($confirmed -and $vscodeSession -and -not $pickerState.VSCodeDone) {
            $pickerState.VSCodeRestore = Restore-VSCodePreview -Session $vscodeSession
            Show-VSCodeRestoreResult -Result $pickerState.VSCodeRestore
        }
        # Clean up the background prefetch job. If it's still mid-fetch (user
```

- [ ] **Step 13: Run the picker tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/WezTerm-LivePreview.Tests.ps1, tests/WezTerm-Writer.Tests.ps1, tests/Picker-NonWT.Tests.ps1, tests/Picker-ShellStateStaging.Tests.ps1, tests/Invoke-PickerLoop.Tests.ps1, tests/Picker-ConsoleGuards.Tests.ps1, tests/Splat-Variables-Defined.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 14: Commit**

```bash
git add tstyles.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Preview the full style in the picker on VS Code"
```

---

### Task 9: `tstyles vscode [on|off]`

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Modify: `tstyles.ps1` (`$script:TStylesSubcommands`, dispatcher)
- Modify: `lib/help.ps1` (new `vscode` entry)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: Tasks 1–4, plus `Get-TerminalKind`.
- Produces:
  - `Show-VSCodeWriterStatus`.
  - `Invoke-TerminalStyleVSCode [-Action <''|'on'|'off'>]`, dispatched as `tstyles vscode [on|off]`.
  - `'vscode'` in `$script:TStylesSubcommands`, so a style can no longer be named `vscode`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'tstyles vscode' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
        }

        It 'is dispatched, with its action' {
            Mock Invoke-TerminalStyleVSCode { }
            Invoke-TerminalStyle -Arg 'vscode' -SubArg 'off'
            Should -Invoke Invoke-TerminalStyleVSCode -Times 1 -Exactly -Scope It -ParameterFilter { $Action -eq 'off' }
        }

        It 'is a reserved word, so no style can shadow it' {
            $script:TStylesSubcommands | Should -Contain 'vscode'
        }

        It 'has a help topic' {
            (Get-TerminalStyleHelpData).Name | Should -Contain 'vscode'
        }

        It 'on records a yes and writes nothing' {
            $out = Invoke-TerminalStyleVSCode -Action 'on' 6>&1 | Out-String
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            $out | Should -Match 'Nothing was written now'
        }

        It 'off takes the saved style out, then records a no' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            $e = (Read-VSCodeState).Entries['Code']
            $e.consent | Should -Be 'no'
            $e.record  | Should -BeNullOrEmpty
        }

        It 'off leaves saving on when the style could not be taken out first' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            [System.IO.File]::WriteAllText($script:sPath, '{ "broken": ', [System.Text.UTF8Encoding]::new($false))
            $out = Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-String
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            $out | Should -Match 'Saving stays on'
        }

        It 'refuses on and off where it cannot tell which editor this is' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            $out = Invoke-TerminalStyleVSCode -Action 'on' 6>&1 | Out-String
            $out | Should -Match "Can't tell which editor"
            [System.IO.File]::Exists((Get-VSCodeStatePath)) | Should -BeFalse
        }

        It 'shows what is recorded' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $out = Invoke-TerminalStyleVSCode 6>&1 | Out-String -Width 500
            $out | Should -Match 'saving: on'
            $out | Should -Match 'style saved: koholint'
            $out | Should -Match ([regex]::Escape($script:sPath))
        }

        It 'answers an action it does not know with how to use it' {
            (Invoke-TerminalStyleVSCode -Action 'sideways' 6>&1 | Out-String) | Should -Match 'tstyles vscode \[on\|off\]'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describe FAILS (`Invoke-TerminalStyleVSCode` is not recognized, and `vscode` is not in the subcommand list).

- [ ] **Step 3: Append the command to `lib/vscodewriter.ps1`**

```powershell

function Show-VSCodeWriterStatus {
    # `tstyles vscode` with no action: what is on record, for this editor and
    # every other one that has been asked.
    [CmdletBinding()]
    param()

    $t = Resolve-VSCodeTarget
    $state = Read-VSCodeState
    Write-Host ""
    if (-not $state.Ok) {
        Write-Host ("  Could not read {0}." -f $state.Path) -ForegroundColor Yellow
        Write-Host "  It records what tstyles wrote to settings.json. Fix it: deleting it lets tstyles" -ForegroundColor Yellow
        Write-Host "  write again, but loses its record of any style already saved there." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    if ($t.Variant) {
        Write-Host ("  This terminal belongs to {0}." -f $t.Variant)
    } elseif ((Get-TerminalKind) -eq 'VSCode') {
        Write-Host "  This looks like a VS Code-family terminal, but tstyles can't tell which" -ForegroundColor Yellow
        Write-Host "  editor it is, so it will not write any settings.json from here." -ForegroundColor Yellow
    }

    $names = @($state.Entries.Keys | Sort-Object)
    if ($t.Variant -and $names -notcontains $t.Variant) { $names = @($t.Variant) + $names }
    if ($names.Count -eq 0) {
        Write-Host "  No VS Code editor has been asked yet." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    foreach ($n in $names) {
        $e = $state.Entries[$n]
        $consent = ''; $style = $null; $path = $null
        if ($e) {
            $consent = $e.consent
            $path = $e.settingsPath
            if ($e.record) { $style = $e.record.Style }
        }
        if (-not $path -and $n -eq $t.Variant) { $path = $t.Path }
        $saving = switch ($consent) {
            'yes'   { 'saving: on' }
            'no'    { 'saving: off' }
            default { 'saving: not asked yet' }
        }
        $saved = 'no style saved'
        if ($style) { $saved = "style saved: $style" }
        Write-Host ("  {0,-16}{1}, {2}" -f $n, $saving, $saved)
        if ($path) { Write-Host ("  {0,-16}{1}" -f '', $path) -ForegroundColor DarkGray }
    }
    Write-Host ""
}

function Invoke-TerminalStyleVSCode {
    <#
    .SYNOPSIS
    `tstyles vscode [on|off]`: the way to change an answer an apply asks for
    only once.

    .DESCRIPTION
    on   records a yes for this editor. It writes nothing now -- the next apply
         does, and saying otherwise would be a claim about a write that has
         not happened.
    off  takes the saved style back out FIRST, then records a no. If the style
         cannot be taken out, saving is left on and the command says so: a no
         on record beside keys still in the file would leave the user believing
         they had been removed.
    #>
    [CmdletBinding()]
    param([string]$Action)

    if (-not $Action) { Show-VSCodeWriterStatus; return }
    if ($Action -ne 'on' -and $Action -ne 'off') {
        Write-Host ""
        Write-Host ("  Unknown vscode action '{0}'. Use: tstyles vscode [on|off]" -f $Action) -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $t = Resolve-VSCodeTarget
    Write-Host ""
    if (-not $t.Variant) {
        Write-Host "  Can't tell which editor this terminal belongs to -- VS Code, Insiders," -ForegroundColor Yellow
        Write-Host "  VSCodium, Cursor or Windsurf -- so there is no settings.json to turn this" -ForegroundColor Yellow
        Write-Host ("  {0} for. Run it from that editor's own terminal." -f $Action) -ForegroundColor Yellow
        Write-Host ""
        return
    }

    if ($Action -eq 'on') {
        try {
            Set-VSCodeStateEntry -Variant $t.Variant -SettingsPath $t.Path -Consent 'yes'
        } catch {
            Write-Host ("  Could not save that to {0}." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host ""
            return
        }
        Write-Host ("  From the next apply, tstyles saves styles to {0}'s settings.json:" -f $t.Variant)
        Write-Host ("    {0}" -f $t.Path) -ForegroundColor DarkGray
        Write-Host "  Nothing was written now." -ForegroundColor DarkGray
        if ($t.Status -eq 'nodir') {
            Write-Host "  That folder does not exist yet, so an apply will say so until the editor" -ForegroundColor Yellow
            Write-Host "  has created it." -ForegroundColor Yellow
        }
        Write-Host ""
        return
    }

    $r = Reset-StyleVSCodeConfig -Variant $t.Variant
    Show-VSCodeResetResult -Result $r
    if ($r.Status -ne 'reset' -and $r.Status -ne 'norecord') {
        Write-Host "  Saving stays on until the style can be taken out first." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    try {
        Set-VSCodeStateEntry -Variant $t.Variant -SettingsPath $t.Path -Consent 'no'
    } catch {
        Write-Host ("  Could not save that to {0}." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        Write-Host ""
        return
    }
    Write-Host ("  tstyles will not write {0}'s settings.json again." -f $t.Variant)
    Write-Host "  tstyles vscode on turns it back on."
    Write-Host ""
}
```

- [ ] **Step 4: Reserve the word and dispatch it (`tstyles.ps1`)**

Replace:

```powershell
    'update', 'uninstall', 'profiles')
```

with:

```powershell
    'update', 'uninstall', 'profiles', 'vscode')
```

Replace:

```powershell
    if ($Arg -eq 'profiles')             { Invoke-TerminalStyleProfiles -Clean:$Clean -Yes:$Yes; return }
```

with:

```powershell
    if ($Arg -eq 'profiles')             { Invoke-TerminalStyleProfiles -Clean:$Clean -Yes:$Yes; return }
    if ($Arg -eq 'vscode')               { Invoke-TerminalStyleVSCode -Action $SubArg; return }
```

- [ ] **Step 5: Add the help topic (`lib/help.ps1`)**

Insert immediately before the entry that begins `            Name = 'uninstall'; Usage = 'uninstall'` (that is, before its `[pscustomobject]@{` line):

```powershell
        [pscustomobject]@{
            Name = 'vscode'; Usage = 'vscode [on|off]'
            Summary = "Whether styles are saved to VS Code's settings.json"
            Detail = @("In a VS Code terminal (or Insiders, VSCodium, Cursor, Windsurf),",
                       "colors apply live like anywhere else. Saving a style -- so new",
                       "terminals and restarts keep its colors, font and cursor -- means",
                       "writing that editor's settings.json, and tstyles asks once per",
                       "editor before it does.",
                       "",
                       "  vscode       Show what is on record: which editor, its",
                       "               settings.json, whether saving is on, and the",
                       "               style saved there.",
                       "  vscode on    Turn saving on for this editor. Takes effect from",
                       "               the next apply; nothing is written now.",
                       "  vscode off   Take the saved style back out of settings.json,",
                       "               then turn saving off.",
                       "",
                       "Only the keys a style sets are written, each with a record of what",
                       "was there before, so a reset puts your own values back; a key you",
                       "change by hand afterwards is left alone. The first write keeps a",
                       "copy of the file beside it as settings.json.bak-<timestamp>.",
                       "There is no background image: VS Code has no setting for one.")
            Keys = @(); Examples = @('tstyles vscode', 'tstyles vscode on', 'tstyles vscode off')
        }
```

- [ ] **Step 6: Run the affected tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/Get-TerminalStyleHelpData.Tests.ps1, tests/Show-TerminalStyleHelp.Tests.ps1, tests/Subcommand-Robustness.Tests.ps1, tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1 -Output Detailed"`
Expected: all PASS. The help drift guard requires the new subcommand to have a topic, and it now does.

- [ ] **Step 7: Commit**

```bash
git add lib/vscodewriter.ps1 tstyles.ps1 lib/help.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Add tstyles vscode [on|off]"
```

---

### Task 10: Uninstall takes saved styles back out

**Files:**
- Modify: `lib/vscodewriter.ps1` (append)
- Modify: `lib/update.ps1` (`Invoke-TerminalStylesUninstall`)
- Modify: `lib/help.ps1` (the `uninstall` topic's Detail)
- Test: `tests/VSCode-Writer.Tests.ps1` (append)

**Interfaces:**
- Consumes: `Read-VSCodeState`, `Reset-StyleVSCodeConfig -Variant`, `Show-VSCodeResetResult`.
- Produces: `Get-VSCodeUninstallTarget -State` → the editors with a saved record, as `[pscustomobject]@{ Variant; Path }` sorted by variant. It returns nothing when the state is not Ok.

- [ ] **Step 1: Write the failing tests**

Append to `tests/VSCode-Writer.Tests.ps1`:

```powershell
Describe 'tstyles uninstall and VS Code''s settings.json' {
    # Driven through the real command, past consent, with every path it can
    # reach inside TestDrive -- the setup Uninstall-ReversesShellInit uses:
    # -HomeDir for the rc half, a mocked data root, the Bootstrap branch so
    # Uninstall-PSResource is never reached, and no $PROFILE target.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Get-PowerShellProfileTarget { @() }

            # Two editors with a saved style, as an uninstall run from a plain
            # terminal finds them.
            $script:user = "{`n  `"editor.fontSize`": 13`n}"
            $script:files = @{}
            foreach ($v in 'Code', 'Cursor') {
                $p = Join-Path $script:h "$v/User/settings.json"
                New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($p)) -Force | Out-Null
                $a = Invoke-VSCodeStyleApply -Text $script:user -StyleDir (Get-StyleDir -StyleName 'koholint') -StyleName 'koholint'
                [System.IO.File]::WriteAllText($p, $a.Text, [System.Text.UTF8Encoding]::new($false))
                Set-VSCodeStateEntry -Variant $v -SettingsPath $p -Consent 'yes' -Record $a.Record
                $script:files[$v] = $p
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedData }

        It 'names every settings.json it will change, and changes none when refused' {
            Mock Confirm-Action { $false }
            $before = @{}
            foreach ($v in $script:files.Keys) { $before[$v] = [System.IO.File]::ReadAllText($script:files[$v]) }
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            foreach ($v in $script:files.Keys) {
                $out | Should -Match ([regex]::Escape($script:files[$v])) -Because 'the prompt must name the file it is about to edit'
                [System.IO.File]::ReadAllText($script:files[$v]) | Should -BeExactly $before[$v]
            }
            $out | Should -Match 'Cancelled'
        }

        It 'takes the style out of every editor once confirmed' {
            Mock Confirm-Action { $true }
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String -Width 500
            foreach ($v in $script:files.Keys) {
                [System.IO.File]::ReadAllText($script:files[$v]) | Should -BeExactly $script:user
                $out | Should -Match ("Took the style back out of {0}'s settings\.json" -f $v)
            }
            $out | Should -Match "Windows Terminal's settings\.json was NOT modified" `
                -Because 'the sign-off must not deny the edit it just made'
        }

        It 'says it will leave VS Code alone when the record cannot be read' {
            Mock Confirm-Action { $false }
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{broken', [System.Text.UTF8Encoding]::new($false))
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Match "Leave VS Code's settings alone"
            $out | Should -Match ([regex]::Escape((Get-VSCodeStatePath)))
        }

        It 'names, in the sign-off, a settings.json it could not take the style out of' {
            Mock Confirm-Action { $true }
            $fs = [System.IO.File]::Open($script:files['Code'], 'Open', 'ReadWrite', 'None')
            try {
                $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String -Width 500
            } finally { $fs.Dispose() }
            $out | Should -Match 'EXCEPT the style saved in'
            $out | Should -Match ([regex]::Escape($script:files['Code']))
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$' -Because 'a style is still in a file the user owns'
            [System.IO.File]::ReadAllText($script:files['Cursor']) | Should -BeExactly $script:user -Because 'the other editor still comes clean'
        }

        It 'the uninstall help says so too' {
            $u = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'uninstall' })
            ($u.Detail -join ' ') | Should -Match 'VS Code'
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1 -Output Detailed"`
Expected: the new Describe FAILS. Paths are not named, the files keep the style, and the sign-off still reads "Your settings.json".

- [ ] **Step 3: Append the target list to `lib/vscodewriter.ps1`**

```powershell

function Get-VSCodeUninstallTarget {
    # The editors whose settings.json holds a saved style: one object per
    # editor, @{ Variant; Path }, from the RECORD rather than from detection --
    # uninstall runs from any terminal, and has to reach every editor.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Ok) { return }
    foreach ($name in @($State.Entries.Keys | Sort-Object)) {
        $e = $State.Entries[$name]
        if ($e.record) { [pscustomobject]@{ Variant = $name; Path = $e.settingsPath } }
    }
}
```

- [ ] **Step 4: List them in the consent screen (`lib/update.ps1`)**

Replace:

```powershell
        Write-Host "      (your wezterm.lua is NOT edited; its require line is pcall-guarded" -ForegroundColor DarkGray
        Write-Host "       and becomes a no-op once this file is gone)" -ForegroundColor DarkGray
    }
```

with:

```powershell
        Write-Host "      (your wezterm.lua is NOT edited; its require line is pcall-guarded" -ForegroundColor DarkGray
        Write-Host "       and becomes a no-op once this file is gone)" -ForegroundColor DarkGray
    }
    # VS Code-family settings.json files a style was saved into. Every editor
    # on record, not just the one this terminal belongs to: uninstall can run
    # from anywhere, and once the module is gone nothing can take those keys
    # out again. Named by path, like every other file this prompt lists.
    $vscodeState   = Read-VSCodeState
    $vscodeTargets = @(Get-VSCodeUninstallTarget -State $vscodeState)
    if ($vscodeTargets.Count -gt 0) {
        Write-Host "  - Take the saved style back out of:" -ForegroundColor Yellow
        foreach ($t in $vscodeTargets) {
            Write-Host ("      {0}: {1}" -f $t.Variant, $t.Path) -ForegroundColor Yellow
        }
    }
    if (-not $vscodeState.Ok) {
        Write-Host ("  - Leave VS Code's settings alone: {0} could not be read" -f $vscodeState.Path) -ForegroundColor Yellow
    }
```

- [ ] **Step 5: Undo them after the WezTerm module**

Replace:

```powershell
            Write-Host "  ! could not remove $wezPath" -ForegroundColor Red
            Write-Host "    Delete it by hand; until then WezTerm keeps applying the last style." -ForegroundColor Red
        }
    }
```

with:

```powershell
            Write-Host "  ! could not remove $wezPath" -ForegroundColor Red
            Write-Host "    Delete it by hand; until then WezTerm keeps applying the last style." -ForegroundColor Red
        }
    }

    # The saved VS Code styles, from their records -- the same list the prompt
    # named. Each says what it did. One that could not be undone is collected
    # for the sign-off: its record survives only until -DeleteData, and once
    # the module is gone no `tstyles reset` can retry it.
    $vscodeProblems = @(foreach ($t in $vscodeTargets) {
        $vr = Reset-StyleVSCodeConfig -Variant $t.Variant
        Show-VSCodeResetResult -Result $vr
        if ($vr.Status -ne 'reset' -and $vr.Status -ne 'norecord') { $t.Path }
    })
```

- [ ] **Step 5b: Do not sign off "uninstalled" over a style still in a settings.json**

Replace:

```powershell
    } else {
        Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    }
```

with:

```powershell
    } elseif ($vscodeProblems.Count -eq 0) {
        Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    }
    # A VS Code style that could not be taken out. Its record is the only thing
    # that names those keys, and with the module gone no reset can use it -- so
    # the user is told where they are, rather than "uninstalled".
    if ($vscodeProblems.Count -gt 0) {
        if ($allProblems.Count -gt 0) {
            Write-Host "...and the style saved in:" -ForegroundColor Yellow
        } else {
            Write-Host "TerminalStyles uninstalled, EXCEPT the style saved in:" -ForegroundColor Yellow
        }
        foreach ($p in $vscodeProblems) { Write-Host ("  {0}" -f $p) -ForegroundColor Yellow }
        Write-Host "Take its terminal settings out of those files by hand, or restore the" -ForegroundColor Yellow
        Write-Host "settings.json.bak-* copy beside each -- the module is gone, so tstyles cannot." -ForegroundColor Yellow
    }
```

- [ ] **Step 6: Make the sign-off name the file it means**

Replace:

```powershell
    Write-Host "Your settings.json was NOT modified. If you want a default look back," -ForegroundColor Gray
    Write-Host "restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
```

with:

```powershell
    Write-Host "Windows Terminal's settings.json was NOT modified. If you want its default look" -ForegroundColor Gray
    Write-Host "back, restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
```

- [ ] **Step 7: Make the `uninstall` help topic true (`lib/help.ps1`)**

Replace:

```powershell
                       "Your saved styles and state are preserved unless you pass -DeleteData.",
```

with:

```powershell
                       "A style saved to a VS Code-family editor's settings.json (VS Code,",
                       "Insiders, VSCodium, Cursor, Windsurf) is taken back out of it, from",
                       "its record; a key you changed by hand since is left alone.",
                       "",
                       "Your saved styles and state are preserved unless you pass -DeleteData.",
```

- [ ] **Step 8: Run the affected tests to verify they pass**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/VSCode-Writer.Tests.ps1, tests/Uninstall-ConsentNamesShellRc.Tests.ps1, tests/Uninstall-ReversesShellInit.Tests.ps1, tests/Consent-Gates.Tests.ps1, tests/Splat-Variables-Defined.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/vscodewriter.ps1 lib/update.ps1 lib/help.ps1 tests/VSCode-Writer.Tests.ps1
git commit -m "Take saved VS Code styles back out on uninstall"
```

---

### Task 11: Fingerprint the real `settings.json` in the real-state guard

**Files:**
- Modify: `tests/Aa-RealStateBaseline.Tests.ps1`
- Modify: `tests/Zz-RealStateUntouched.Tests.ps1`

**Interfaces:**
- Consumes: the module's `Get-AvailableStyles`, `Get-VSCodeStylePlan`, `Get-VSCodeSettingsPath` (its `-Variant` ValidateSet), and `Get-JsoncValueLiteral`.
- Produces: these globals:
  - `$global:TStylesVSCodeKeys`: the top-level keys the plans write.
  - `$global:TStylesVSCodeProbe`: a scriptblock, path list → ordered path → fingerprint.
  - `$global:TStylesVSCodeWatch`: one real path per editor.
  - `$global:TStylesVSCodeBefore`.

- [ ] **Step 1: Write the failing tests**

In `tests/Zz-RealStateUntouched.Tests.ps1`, add these two It blocks after the `'notices a write, so a green result here means something'` It block:

```powershell
    It 'the VS Code fingerprint sees a style written in, and nothing else' {
        $p = Join-Path $TestDrive ('vs-' + [guid]::NewGuid().ToString('n') + '.json')
        [System.IO.File]::WriteAllText($p, "{`n  `"editor.fontSize`": 13`n}")
        $before = & $global:TStylesVSCodeProbe -Path @($p)

        # Not ours, and exactly the kind of write VS Code makes by itself.
        [System.IO.File]::WriteAllText($p, "{`n  `"editor.fontSize`": 14`n}")
        (& $global:TStylesVSCodeProbe -Path @($p))[$p] | Should -Be $before[$p] `
            -Because 'a change TerminalStyles did not make must not fail the run'

        $m = Get-Module TerminalStyles
        $styled = & $m {
            param($Text)
            (Invoke-VSCodeStyleApply -Text $Text -StyleDir (Get-StyleDir -StyleName 'koholint') -StyleName 'koholint').Text
        } ([System.IO.File]::ReadAllText($p))
        [System.IO.File]::WriteAllText($p, $styled)
        (& $global:TStylesVSCodeProbe -Path @($p))[$p] | Should -Not -Be $before[$p] `
            -Because 'a style leaking into the file is what this exists to catch'
    }

    It 'has written no style into any VS Code-family settings.json' {
        $before = $global:TStylesVSCodeBefore
        $before | Should -Not -BeNullOrEmpty -Because 'the baseline is taken in Aa-RealStateBaseline'
        $after = & $global:TStylesVSCodeProbe -Path $global:TStylesVSCodeWatch
        $changes = @(foreach ($k in $before.Keys) {
            if ($after[$k] -cne $before[$k]) { "CHANGED  $k" }
        })
        $changes.Count | Should -Be 0 -Because (
            "a test wrote a style into a real editor's settings.json. Mock Resolve-VSCodeTarget " +
            "to a `$TestDrive path, or bind -HomeDir/-AppData/-XdgConfigHome. Changed:`n    " +
            ($changes -join "`n    ") + "`n")
    }
```

In `tests/Aa-RealStateBaseline.Tests.ps1`, add after the `'actually captured something'` It block:

```powershell
    It 'knows which VS Code files and keys to fingerprint' {
        @($global:TStylesVSCodeWatch).Count | Should -BeGreaterThan 0
        $global:TStylesVSCodeKeys | Should -Contain 'workbench.colorCustomizations' `
            -Because 'every bundled style writes its colours there'
        $global:TStylesVSCodeBefore | Should -Not -BeNullOrEmpty
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/Aa-RealStateBaseline.Tests.ps1, tests/Zz-RealStateUntouched.Tests.ps1 -Output Detailed"`
Expected: FAIL. `$global:TStylesVSCodeProbe` is `$null`, so invoking it errors.

- [ ] **Step 3: Take the VS Code baseline (`tests/Aa-RealStateBaseline.Tests.ps1`)**

Inside `BeforeDiscovery`, replace:

```powershell
    $global:TStylesRealStateBefore = & $global:TStylesRealStateProbe -Path $global:TStylesRealStateWatch
}
```

with:

```powershell
    $global:TStylesRealStateBefore = & $global:TStylesRealStateProbe -Path $global:TStylesRealStateWatch

    # VS Code's settings.json is written by this module too, and is NOT watched
    # by metadata like the paths above: VS Code rewrites it itself -- the
    # settings UI, Settings Sync -- on no schedule a test controls, which is the
    # reason the guard file gives for leaving Windows Terminal's out. So it is
    # fingerprinted by the keys TerminalStyles writes and nothing else: the
    # top-level keys every available style's plan touches, each read back as
    # source text. A sync that changes editor.fontSize is invisible here; a test
    # that leaks a style into the real file is not. The key list and the editor
    # list are both asked of the module, so neither is a second copy.
    $global:TStylesVSCodeKeys = @(& $m {
        $keys = @{}
        foreach ($s in @(Get-AvailableStyles)) {
            try {
                foreach ($e in (Get-VSCodeStylePlan -StyleDir $s.FullName)) { $keys[$e.Path[0]] = $true }
            } catch { }
        }
        @($keys.Keys | Sort-Object)
    })
    $global:TStylesVSCodeProbe = {
        param([string[]]$Path)
        $mod = Get-Module TerminalStyles
        $state = [ordered]@{}
        foreach ($p in $Path) {
            if (-not [System.IO.File]::Exists($p)) { $state[$p] = 'absent'; continue }
            $text = [System.IO.File]::ReadAllText($p)
            $state[$p] = & $mod {
                param($Text, $Keys)
                @($Keys | ForEach-Object { '{0}={1}' -f $_, (Get-JsoncValueLiteral -Text $Text -Path @($_)) }) -join "`n"
            } $text $global:TStylesVSCodeKeys
        }
        $state
    }
    $global:TStylesVSCodeWatch = @(& $m {
        $set = (Get-Command Get-VSCodeSettingsPath).Parameters['Variant'].Attributes |
               Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        foreach ($v in $set.ValidValues) { Get-VSCodeSettingsPath -Variant $v }
    })
    $global:TStylesVSCodeBefore = & $global:TStylesVSCodeProbe -Path $global:TStylesVSCodeWatch
}
```

- [ ] **Step 4: Note it in the Zz header**

In `tests/Zz-RealStateUntouched.Tests.ps1`, replace:

```powershell
# gets deleted. They stay covered by the -Path/-Targets seams alone.
```

with:

```powershell
# gets deleted. They stay covered by the -Path/-Targets seams alone. VS Code's
# settings.json is the same kind of file and is NOT left alone: it is
# fingerprinted by the keys this module writes rather than by its metadata (see
# Aa-RealStateBaseline), so VS Code's own rewrites cannot fail a run and a
# leaked style still does.
```

- [ ] **Step 5: Run the full suite, which these two files bracket**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests -Output Normal"`
Expected: 0 failed. The two guard files must pass with every other file run between them. That is the point: no test in this plan may have touched a real editor's file.

- [ ] **Step 6: Commit**

```bash
git add tests/Aa-RealStateBaseline.Tests.ps1 tests/Zz-RealStateUntouched.Tests.ps1
git commit -m "Fingerprint VS Code's settings.json in the real-state guard"
```

---

### Task 12: Documentation

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `CLAUDE.md`
- Test: the README and changelog guards that already exist (no new tests)

- [ ] **Step 1: README capability table and the paragraph under it**

Replace the row `| VS Code terminal | ✅ | color only | — | — | — | — |` with:

```markdown
| VS Code terminal ¹ | ✅ | ✅ shape + color | ✅ | — | — | — |
```

Replace:

```markdown
terminal reads at startup, and TerminalStyles knows how to write three of
those: Windows Terminal's `settings.json`, Terminal.app's `.terminal` profile,
and WezTerm's generated Lua module.
```

with:

```markdown
terminal reads at startup, and TerminalStyles knows how to write four of
those: Windows Terminal's `settings.json`, Terminal.app's `.terminal` profile,
WezTerm's generated Lua module, and a VS Code-family editor's `settings.json`.

¹ VS Code, Insiders, VSCodium, Cursor and Windsurf, once you have said yes to
TerminalStyles saving styles in that editor's `settings.json` — it asks the
first time. Until then, and in an editor it cannot identify, colors only. See
[VS Code, Cursor, VSCodium and Windsurf](#vs-code-cursor-vscodium-and-windsurf).
```

- [ ] **Step 2: README section for VS Code**

Insert immediately before the line `## Background image`, the top-level heading that follows "Background images on Terminal.app":

````markdown
### VS Code, Cursor, VSCodium and Windsurf

The integrated terminal takes the colors live like any other. To make a style
*stay* — in new terminals and after a restart, font and cursor included —
TerminalStyles writes it into that editor's own `settings.json`, and asks once
per editor before it does. `tstyles vscode` shows the answer on record;
`tstyles vscode on` and `tstyles vscode off` change it (`off` takes the saved
style back out first).

What is written: the terminal's 20 colors under `workbench.colorCustomizations`,
and `terminal.integrated.fontFamily`, `fontSize`, `fontWeight` and
`cursorStyle`. Nothing else in the file is touched, comments and formatting
included. Each apply keeps a record of what was there before, so `tstyles reset`
(in that editor's terminal), `tstyles vscode off` and `tstyles uninstall` put
your own values back; a key you change by hand afterwards is left alone and
named. The first time a style goes into the file, a copy of it is kept beside
it as `settings.json.bak-<timestamp>`.

The picker previews the whole style as you arrow, font and cursor too, and Esc
puts the file back exactly as it was. If `settings.json` changes while the
picker is open (you edit it, or Settings Sync does), no further preview is
written into it, and Enter and Esc both work from the file as it is now. Esc
takes the preview out by its record instead of putting the old file back.
Either way your change stays, except for a key the incoming style also sets.
That key is named, and `tstyles reset` puts your value back.

- **No background image.** VS Code has no setting for one.
- **The editor has to be identifiable.** All five set `TERM_PROGRAM=vscode`, so
  TerminalStyles tells them apart by the install path VS Code's git integration
  exports as `VSCODE_GIT_ASKPASS_NODE`. With `git.terminalAuthentication` turned
  off VS Code does not set it, and TerminalStyles refuses to write rather than
  guess which editor's file to change.
- **A color theme can win.** A theme-scoped block such as
  `"[Monokai]": { "terminal.background": "#000000" }` inside
  `workbench.colorCustomizations` overrides the style while that theme is
  active; the apply names any it finds.
- **Workspace settings win over user settings.** A project's own
  `.vscode/settings.json` can set the same keys, and that is not detected.
- **Settings Sync carries it.** If you sync settings, the style goes to your
  other machines with them.

````

- [ ] **Step 3: README recovery section**

Replace:

```markdown
the most recent write", use `apply.ps1` — it keeps a timestamped backup
per run.
```

with:

````markdown
the most recent write", use `apply.ps1` — it keeps a timestamped backup
per run.

**VS Code** keeps its own copy. The first write of a style into a VS
Code-family `settings.json` copies the file beside it as
`settings.json.bak-<timestamp>`, taken before any TerminalStyles key was in
it. Try `tstyles reset` from that editor's terminal first; the copy is the way
back from anything a reset cannot fix:

```powershell
# macOS; on Windows the folder is "$env:APPDATA\Code\User", on Linux ~/.config/Code/User
$vs = "$HOME/Library/Application Support/Code/User/settings.json"
Copy-Item "$vs.bak-<timestamp>" $vs -Force
```
````

- [ ] **Step 4: README uninstall section**

Replace:

```markdown
Neither path modifies Windows Terminal's `settings.json` — your
current color scheme / cursor / background stays whatever it was
last set to.
```

with:

```markdown
Neither path modifies Windows Terminal's `settings.json` — your
current color scheme / cursor / background stays whatever it was
last set to.

VS Code is the exception. A style saved into a VS Code-family
editor's `settings.json` is taken back out, from its record, for
every editor that has one — the confirmation names each file first,
and a key you changed by hand since is left alone.
```

- [ ] **Step 5: README known limitations**

Replace:

```markdown
  file, and off Windows Terminal the only config file this tool writes is
  WezTerm's generated Lua module — which now carries all five, so a WezTerm
```

with:

```markdown
  file. Off Windows Terminal, WezTerm's generated Lua module carries all
  five, so a WezTerm
```

Replace:

```markdown
  which WezTerm has no equivalent for. Both doors — `tstyles <name>` and the
```

with:

```markdown
  which WezTerm has no equivalent for. A VS Code-family editor's
  `settings.json` carries the font and the cursor shape once you have said
  yes to it being written, and has no setting for the other three. Both
  doors — `tstyles <name>` and the
```

Replace:

```markdown
  capability table as the grid above, rather than dropping them silently. Hosts
  that render nothing (VS Code's integrated terminal, conhost) stay plain by
  design.
```

with:

```markdown
  capability table as the grid above, rather than dropping them silently. Hosts
  that render nothing (conhost) stay plain by design.
```

- [ ] **Step 6: CHANGELOG**

Replace:

```markdown
## [Unreleased]

## [0.8.48] - 2026-09-27
```

with:

```markdown
## [Unreleased]

### Added

- **Styles stick in VS Code's terminal -- and in Insiders, VSCodium, Cursor and Windsurf.** Until now a style applied there was escape sequences only: the colors held for that tab, and the font and cursor never arrived. `tstyles <name>`, the picker, `random`, `tune` and `delete` now write the style into the editor's own `settings.json` -- the terminal's 20 colour ids under `workbench.colorCustomizations`, plus `terminal.integrated.fontFamily`, `fontSize`, `fontWeight` and `cursorStyle` -- so new terminals and restarts keep it, and the picker previews the font and cursor as you arrow, not just the palette.

  It **asks first**, once per editor, and remembers the answer in `vscode-state.json` under the data root; `tstyles vscode on|off` changes it. A file people annotate by hand and sync between machines is not one to start writing on the strength of an apply, and nobody at the terminal to answer is not taken as a no.

  Every apply keeps a **record** of what it set and what was there before, saved before the file is written and rolled back if the write fails. `tstyles reset`, `tstyles vscode off` and `tstyles uninstall` undo from it: earlier values come back byte for byte, a key changed by hand since is left alone and named, and a style deleted in the meantime can still be taken out. Switching styles takes the previous one off first, so a reset after several switches still returns the file it started from. Comments and formatting survive, because the file is spliced as text rather than parsed and re-serialised. An edit made while the picker is open survives it: no preview is written over the changed file, and Esc takes its preview out by record instead of putting back the copy it took when it opened. The first write to a file keeps a `settings.json.bak-<timestamp>` copy beside it.

  It **refuses rather than guesses**: an editor it cannot identify (it reads the install path VS Code's git integration exports as `VSCODE_GIT_ASKPASS_NODE`), a settings folder that does not exist, and a file that does not parse all stop the write and say which -- the alternative was a Cursor user's style landing in VS Code's file and reporting success. A theme-scoped block (`"[Monokai]": { "terminal.background": ... }`) that would win over the written colours is named after the apply. Font sizes are converted from points to pixels, so a style is not drawn a quarter smaller than it asks.

  No background image: VS Code has no setting for one. A workspace's own `.vscode/settings.json` can override the user file and is not detected.

### Changed

- **`vscode` is a subcommand**, so a style can no longer be named `vscode` -- the dispatcher matches the word first and such a style could never be applied, the reason `reset` is reserved.

### Fixed

- **A `settings.json` that will not parse is named, rather than always called Windows Terminal's.** The parse error hard-coded "Windows Terminal settings.json" and its remedy ("open WT Settings and Save once"), and added the Windows PowerShell 5.1 comment sentence on every engine. The file and the remedy are now the caller's to name, and the 5.1 sentence appears only on 5.1, where it is the cause.

## [0.8.48] - 2026-09-27
```

- [ ] **Step 7: CLAUDE.md**

Replace:

```markdown
that predate it — `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`, the
PowerShell `$PROFILE`, Windows Terminal's `settings.json`.
```

with:

```markdown
that predate it — `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`, the
PowerShell `$PROFILE`, Windows Terminal's `settings.json`, and a VS Code-family
editor's `settings.json`.

VS Code's path comes from `Resolve-VSCodeTarget`, which takes `-HomeDir` /
`-AppData` / `-XdgConfigHome`; a bound `-HomeDir` suppresses the ambient `APPDATA`
and `XDG_CONFIG_HOME`. Writer tests mock `Resolve-VSCodeTarget` to a `$TestDrive`
path AND sandbox the data root, which holds the consent and undo records in
`vscode-state.json`. The real-state guard fingerprints the keys TerminalStyles
writes in every VS Code-family `settings.json` rather than watching mtimes,
because VS Code rewrites that file itself.
```

Replace:

```markdown
There are exactly three config writers in the repo: `Merge-StyleIntoSettings` (Windows
Terminal `settings.json`), `New-AppleTerminalProfile` (Terminal.app `.terminal` plist)
and `Get-WezTermStyleLua` (WezTerm's generated Lua module). Everything else is escape
sequences.
```

with:

```markdown
There are exactly four config writers in the repo: `Merge-StyleIntoSettings` (Windows
Terminal `settings.json`), `New-AppleTerminalProfile` (Terminal.app `.terminal` plist),
`Get-WezTermStyleLua` (WezTerm's generated Lua module) and `Invoke-VSCodeStyleApply`
(a VS Code-family editor's `settings.json`, written from `lib/vscodewriter.ps1` —
`Publish-StyleVSCodeConfig` and the picker's preview session — only after the user has
said yes for that editor, so its capability flags are conditional too, on
`Test-VSCodeWriterActive`). Everything else is escape sequences.
```

- [ ] **Step 8: Run the doc guards**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path tests/Contributing-MatchesCI.Tests.ps1, tests/README-Theme-Count.Tests.ps1, tests/README-Banner.Tests.ps1, tests/README-Install-Size.Tests.ps1, tests/Font-ApplyPromise.Tests.ps1, tests/Release-Metadata.Tests.ps1, tests/Unshipped-Versions.Tests.ps1 -Output Detailed"`
Expected: all PASS. The recovery-section lint must still find "picker" and must not find "picker … does not/never/skips" within 80 characters; the new paragraph avoids both.

- [ ] **Step 9: Commit**

```bash
git add README.md CHANGELOG.md CLAUDE.md
git commit -m "Document the VS Code writer"
```

---

### Task 13: Verify on every leg, end to end, and hand over

**Files:** none changed, unless verification finds a defect. In that case, fix it in the task that owns the code and commit it there.

- [ ] **Step 1: Full suite locally (pwsh 7, macOS)**

Run: `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; \$c = New-PesterConfiguration; \$c.Run.Path = 'tests'; \$c.Output.Verbosity = 'Normal'; Invoke-Pester -Configuration \$c"`
Expected: `Failed: 0`. Record the passed/skipped counts for the PR description.

- [ ] **Step 2: End to end against a temporary home, with VS Code's environment faked**

Write `$SCRATCH/e2e-vscode.ps1`, where `$SCRATCH` is the session scratchpad directory:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module /Users/cremerius/TerminalStyles/TerminalStyles.psd1 -Force -DisableNameChecking *> $null
$sPath = Join-Path $HOME 'Library/Application Support/Code/User/settings.json'
New-Item -ItemType Directory -Path (Split-Path $sPath) -Force | Out-Null
$user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
[System.IO.File]::WriteAllText($sPath, $user, [System.Text.UTF8Encoding]::new($false))
function Step($name, [scriptblock]$check) { if (& $check) { "PASS  $name" } else { "FAIL  $name"; exit 1 } }

tstyles vscode on *> $null
Step 'on writes nothing'           { [IO.File]::ReadAllText($sPath) -ceq $user }
tstyles koholint *> $null
Step 'apply writes the style'      { [IO.File]::ReadAllText($sPath) -match 'terminal\.background' }
Step 'first-touch copy exists'     { @(Get-ChildItem (Split-Path $sPath) -Filter 'settings.json.bak-*').Count -eq 1 }
tstyles eva *> $null
Step 'switch keeps one copy'       { @(Get-ChildItem (Split-Path $sPath) -Filter 'settings.json.bak-*').Count -eq 1 }
tstyles reset *> $null
Step 'reset is byte for byte'      { [IO.File]::ReadAllText($sPath) -ceq $user }
tstyles sober *> $null
tstyles vscode off *> $null
Step 'off takes it out'            { [IO.File]::ReadAllText($sPath) -ceq $user }
tstyles lain *> $null
Step 'off means off'               { [IO.File]::ReadAllText($sPath) -ceq $user }
"ALL PASS"
```

Run it with a throwaway HOME, so neither the data root nor the settings path can be the real one. Use an emptied environment, so no inherited terminal marker (`ITERM_SESSION_ID`, `WEZTERM_PANE`, a real `GIT_ASKPASS`) can change which terminal or editor is detected:

```bash
SB="$(mktemp -d)" && env -i HOME="$SB" PATH="$PATH" TERM_PROGRAM=vscode \
  VSCODE_GIT_ASKPASS_NODE="/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)" \
  pwsh -NoProfile -File "$SCRATCH/e2e-vscode.ps1"; echo "exit=$?"; rm -rf "$SB"
```

Expected: eight `PASS` lines, then `ALL PASS`, `exit=0`. The first apply may pause on the throttled update check (there is no switch to skip it). That check fails quietly when offline.

The picker is not driven here, because it needs a real keyboard; Task 7 pins its behaviour. If a `FAIL` appears, stop and debug with superpowers:systematic-debugging. Do not edit the script to pass.

- [ ] **Step 3: Ask the maintainer before pushing**

Pushing publishes the branch, so ask first. On a yes:

```bash
git push -u origin feat/vscode-settings-writer
```

Then poll CI. Do not use `gh pr checks --watch`: it exits while checks are pending, and a fresh push has no checks yet.

```bash
gh run list --branch feat/vscode-settings-writer --limit 3
gh run view <run-id> --json jobs -q '.jobs[] | .name + ": " + .conclusion'
```

Expected: all four legs `success`: pwsh 7, Windows PowerShell 5.1, macos-latest and ubuntu-latest. The 5.1 leg is the one that proves the record round trip (Task 1) and the ASCII literals.

- [ ] **Step 4: Hand over the visual check**

The maintainer runs this in a real VS Code terminal. Back the file up first:

```bash
cp "$HOME/Library/Application Support/Code/User/settings.json" ~/settings.json.before-tstyles
```

Then:
1. Run `tstyles koholint` and answer `y`. The terminal font and cursor should change, and new terminals should open styled.
2. Run `tstyles` and arrow through the styles. The font and cursor should follow a moment after the colours. Press Esc: the file should be back exactly as it was (`diff` it against the backup).
3. Run `tstyles reset`. The file should match the backup.

- [ ] **Step 5: Offer the PR**

With CI green and the visual check done, open the PR on the maintainer's yes. Base it on `main`, with a plain body and no "Generated with" footer. The body should list:
- what changed;
- the measured preview cost;
- the two pre-existing picker defects found and left alone: the non-WT confirm prints the "can't show" notice twice, and the WezTerm publisher's picker notices are wiped by the confirm `Clear-Host`.
