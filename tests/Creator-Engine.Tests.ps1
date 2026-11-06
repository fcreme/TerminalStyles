# Pester 5 tests for lib/creatorengine.ps1: the creator's pages and keys.
#
# The engine is pure: Invoke-CreatorKey takes a state and a key and returns the
# new state and what the loop should do, and Get-CreatorPageLines returns the
# page as strings. The image reader is injected, so nothing here needs Windows
# or a real image. The data root points at $TestDrive wherever a name is
# checked, because Get-StyleDir looks there for the user's styles.
#
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

Describe 'ConvertFrom-PastedPath' {
    InModuleScope TerminalStyles {
        It 'strips the quotes Explorer''s Copy as path adds, keeping the spaces inside' {
            ConvertFrom-PastedPath '"C:\My Pictures\city.png"' | Should -BeExactly 'C:\My Pictures\city.png'
        }
        It 'strips single quotes and surrounding whitespace' {
            ConvertFrom-PastedPath "  '/home/me/my pics/a.png'  " | Should -BeExactly '/home/me/my pics/a.png'
        }
        It 'strips one pair only' {
            ConvertFrom-PastedPath '""a.png""' | Should -BeExactly '"a.png"'
        }
        It 'leaves an unmatched quote alone' {
            ConvertFrom-PastedPath '"a.png' | Should -BeExactly '"a.png'
            ConvertFrom-PastedPath '"a.png''' | Should -BeExactly '"a.png'''
        }
        It 'trims a plain path' {
            ConvertFrom-PastedPath "  a.png`t" | Should -BeExactly 'a.png'
        }
    }
}

Describe 'Invoke-CreatorKey' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:px = [int[]]@(
                foreach ($c in 0x0a0a2a, 0x1a1a4a, 0xff7a1a, 0xc2306a, 0x2fa04a, 0x3060d0, 0xe0e0f0) {
                    for ($i = 0; $i -lt 40; $i++) { $c }
                }
            )
            $script:goodReader = { param($p) $script:readPaths.Add($p); $script:px }
            $script:badReader = { param($p) throw "Not an image TerminalStyles can read: $p" }
            # A loaded state on a given step, as the engine leaves it.
            $script:onStep = {
                param([int]$Step)
                $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
                $s.Step = $Step
                $s
            }
            $script:key = {
                param($State, $Key, $Text)
                $a = @{ State = $State; ReadImage = $script:goodReader }
                if ($null -ne $Key) { $a.Key = $Key }
                if ($null -ne $Text) { $a.Text = $Text }
                Invoke-CreatorKey @a
            }
        }
        BeforeEach {
            $script:readPaths = New-Object System.Collections.Generic.List[string]
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            Push-Location -LiteralPath $TestDrive
        }
        AfterEach {
            Pop-Location
            $script:TStylesDataRoot = $script:savedRoot
        }

        Context 'step 0, before an image' {
            It 'the start state is step 0 with an empty path and no scheme' {
                $s = New-CreatorStartState
                $s.Step | Should -Be 0
                $s.PathText | Should -BeExactly ''
                $s.Scheme | Should -BeNullOrEmpty
            }

            It 'typed characters append to the path field' {
                $s = New-CreatorStartState
                $r = & $script:key $s $null 'pic'
                $r = & $script:key $r.State $null 's/a.png'
                $r.State.PathText | Should -BeExactly 'pics/a.png'
                $r.Action | Should -BeExactly 'none'
            }

            It 'a typed character arrives as a ConsoleKeyInfo too' {
                $s = New-CreatorStartState
                $k = New-Object System.ConsoleKeyInfo ([char]'a'), ([ConsoleKey]::A), $false, $false, $false
                $r = & $script:key $s $k $null
                $r.State.PathText | Should -BeExactly 'a'
            }

            It 'Backspace in the path field deletes a character and never goes back' {
                $s = New-CreatorStartState
                $s.PathText = 'ab'
                $r = & $script:key $s 'Backspace' $null
                $r.State.PathText | Should -BeExactly 'a'
                $r.State.Step | Should -Be 0
                $r.Action | Should -BeExactly 'none'
                $r = & $script:key $r.State 'Backspace' $null
                $r = & $script:key $r.State 'Backspace' $null
                $r.State.PathText | Should -BeExactly ''
                $r.State.Step | Should -Be 0
                $r.Action | Should -BeExactly 'none'
            }

            It 'Enter with an empty path says what to do and stays' {
                $r = & $script:key (New-CreatorStartState) 'Enter' $null
                $r.Action | Should -BeLike 'error:*'
                $r.State.Step | Should -Be 0
                $script:readPaths.Count | Should -Be 0
            }

            It 'Enter on a file the reader refuses returns its message and stays on step 0' {
                $s = New-CreatorStartState
                $s.PathText = 'notes.png'
                $r = Invoke-CreatorKey -State $s -Key 'Enter' -ReadImage $script:badReader
                $r.Action | Should -BeLike 'error:Not an image TerminalStyles can read: *'
                $r.State.Step | Should -Be 0
                $r.State.Scheme | Should -BeNullOrEmpty
                $r.State.PathText | Should -BeExactly 'notes.png'
            }

            It 'Enter on a type the save would refuse (<f>) says which types it takes, without reading it' -ForEach @(
                @{ f = 'photo.bmp' }, @{ f = 'scan.tif' }, @{ f = 'noext' }) {
                $s = New-CreatorStartState
                $s.PathText = $f
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeExactly ("error:'$f' is not a file type tstyles create takes. Use a .gif, .png, .jpg, .jpeg or .jfif file.")
                $r.State.Step | Should -Be 0
                $r.State.Scheme | Should -BeNullOrEmpty
                $script:readPaths.Count | Should -Be 0 -Because 'the type is refused before the reader runs'
            }

            It 'Enter on a .jfif (a JPEG as Windows browsers save one) reads it' {
                $s = New-CreatorStartState
                $s.PathText = 'download.JFIF'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeExactly 'preview'
                $script:readPaths.Count | Should -Be 1
            }

            It 'a relative, quoted path reaches the reader and the state absolute and unquoted' {
                $s = New-CreatorStartState
                $s.PathText = '"pics/my city.png"'
                $r = & $script:key $s 'Enter' $null
                $want = [System.IO.Path]::GetFullPath((Join-Path (Get-Location -PSProvider FileSystem).ProviderPath 'pics/my city.png'))
                $script:readPaths.Count | Should -Be 1
                $script:readPaths[0] | Should -BeExactly $want
                $r.State.ImagePath | Should -BeExactly $want
                [System.IO.Path]::IsPathRooted($r.State.ImagePath) | Should -BeTrue
            }

            It 'a good image builds the full state, stays on step 0 and asks for a preview; Enter again moves on' {
                $s = New-CreatorStartState
                $s.PathText = 'a.png'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.Step | Should -Be 0
                $r.State.Scheme | Should -Not -BeNullOrEmpty
                $r.State.ImageOpacity | Should -Be 0.35
                $r = & $script:key $r.State 'Enter' $null
                $r.Action | Should -BeExactly 'next'
                $r.State.Step | Should -Be 1
                $script:readPaths.Count | Should -Be 1
            }

            It 'a different path typed after a good image is read again, keeping the image settings' {
                $s = New-CreatorStartState
                $s.PathText = 'a.png'
                $r = & $script:key $s 'Enter' $null
                $r.State.ImageOpacity = 0.6
                $r.State.PathText = 'b.png'
                $r = & $script:key $r.State 'Enter' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.Step | Should -Be 0
                $r.State.ImagePath | Should -BeLike '*b.png'
                $r.State.ImageOpacity | Should -Be 0.6
                $script:readPaths.Count | Should -Be 2
            }

            It 'Esc cancels before an image' {
                (& $script:key (New-CreatorStartState) 'Escape' $null).Action | Should -BeExactly 'cancel'
            }
        }

        Context 'step 0, image settings' {
            BeforeEach {
                $s = New-CreatorStartState
                $s.PathText = 'a.png'
                $script:loaded = (& $script:key $s 'Enter' $null).State
            }

            It 'Down then Right raises the opacity by 0.05' {
                $r = & $script:key $script:loaded 'DownArrow' $null
                $r = & $script:key $r.State 'RightArrow' $null
                $r.Action | Should -BeExactly 'preview'
                [Math]::Round($r.State.ImageOpacity, 2) | Should -Be 0.40
                $r = & $script:key $r.State 'LeftArrow' $null
                $r = & $script:key $r.State 'LeftArrow' $null
                [Math]::Round($r.State.ImageOpacity, 2) | Should -Be 0.30
            }

            It 'the opacity is clamped to 0..1' {
                $r = & $script:key $script:loaded 'DownArrow' $null
                $r.State.ImageOpacity = 0.98
                $r = & $script:key $r.State 'RightArrow' $null
                $r.State.ImageOpacity | Should -Be 1.0
                $r = & $script:key $r.State 'RightArrow' $null
                $r.State.ImageOpacity | Should -Be 1.0
                $r.Action | Should -BeExactly 'none'
                $r.State.ImageOpacity = 0.02
                $r = & $script:key $r.State 'LeftArrow' $null
                $r.State.ImageOpacity | Should -Be 0.0
            }

            It 'the fit cycles through Windows Terminal''s stretch modes' {
                $r = & $script:key $script:loaded 'DownArrow' $null
                $r = & $script:key $r.State 'DownArrow' $null
                $seen = @()
                for ($i = 0; $i -lt 4; $i++) {
                    $r = & $script:key $r.State 'RightArrow' $null
                    $r.Action | Should -BeExactly 'preview'
                    $seen += $r.State.StretchMode
                }
                $seen | Should -Be @('none', 'fill', 'uniform', 'uniformToFill')
                $r = & $script:key $r.State 'LeftArrow' $null
                $r.State.StretchMode | Should -BeExactly 'uniform'
            }

            It 'the alignment cycles through Windows Terminal''s nine positions' {
                $r = & $script:key $script:loaded 'DownArrow' $null
                $r = & $script:key $r.State 'DownArrow' $null
                $r = & $script:key $r.State 'DownArrow' $null
                $seen = @()
                for ($i = 0; $i -lt 9; $i++) {
                    $r = & $script:key $r.State 'RightArrow' $null
                    $seen += $r.State.Alignment
                }
                @($seen | Sort-Object -Unique).Count | Should -Be 9
                $seen[-1] | Should -BeExactly 'center'
                foreach ($a in $seen) {
                    $a | Should -BeIn @('center', 'left', 'top', 'right', 'bottom', 'topLeft', 'topRight', 'bottomLeft', 'bottomRight')
                }
            }

            It 'Backspace on an image setting changes nothing' {
                $r = & $script:key $script:loaded 'DownArrow' $null
                $r = & $script:key $r.State 'Backspace' $null
                $r.Action | Should -BeExactly 'none'
                $r.State.Step | Should -Be 0
                $r.State.PathText | Should -BeExactly 'a.png'
            }
        }

        Context 'navigation' {
            It 'Enter on step 1 moves to step 2' {
                $r = & $script:key (& $script:onStep 1) 'Enter' $null
                $r.Action | Should -BeExactly 'next'
                $r.State.Step | Should -Be 2
            }
            It 'PageUp on step <_> goes back one step' -ForEach @(1, 2, 3) {
                $r = & $script:key (& $script:onStep $_) 'PageUp' $null
                $r.Action | Should -BeExactly 'back'
                $r.State.Step | Should -Be ($_ - 1)
            }
            It 'PageUp on step 0 does nothing' {
                $s = & $script:onStep 0
                $r = & $script:key $s 'PageUp' $null
                $r.Action | Should -BeExactly 'none'
                $r.State.Step | Should -Be 0
                $r.State.PathText | Should -BeExactly '/img/a.png'
                $r = & $script:key (New-CreatorStartState) 'PageUp' $null
                $r.Action | Should -BeExactly 'none'
                $r.State.Step | Should -Be 0
            }
            It 'ten held Backspaces from step 3 stop on step 0 with the image path untouched' {
                $s = & $script:onStep 3
                $path = $s.ImagePath
                $r = @{ State = $s }
                for ($i = 0; $i -lt 10; $i++) { $r = & $script:key $r.State 'Backspace' $null }
                $r.State.Step | Should -Be 0
                $r.State.PathText | Should -BeExactly $path
                $r.State.ImagePath | Should -BeExactly $path
                $r.State.Control | Should -Be 1
            }
            It 'back to step 0 focuses opacity, not the path field' {
                $r = & $script:key (& $script:onStep 1) 'Backspace' $null
                $r.State.Step | Should -Be 0
                $r.State.Control | Should -Be 1
            }
            It 'PageUp and Backspace in hex entry do not navigate' {
                $s = & $script:onStep 1
                $r = & $script:key $s 'H' $null
                $r = & $script:key $r.State 'Backspace' $null
                $r = & $script:key $r.State 'PageUp' $null
                $r.State.Step | Should -Be 1
                $r.State.HexEntry | Should -BeExactly ''
                $r.Action | Should -BeExactly 'none'
            }
            It 'Backspace on step 2 goes back to step 1' {
                $r = & $script:key (& $script:onStep 2) 'Backspace' $null
                $r.Action | Should -BeExactly 'back'
                $r.State.Step | Should -Be 1
            }
            It 'Esc cancels on step <_>' -ForEach @(0, 1, 2, 3, 4) {
                $r = & $script:key (& $script:onStep $_) 'Escape' $null
                $r.Action | Should -BeExactly 'cancel'
            }
            It 'a new step starts on its first control' {
                $s = & $script:onStep 1
                $r = & $script:key $s 'DownArrow' $null
                $r = & $script:key $r.State 'Enter' $null
                $r.State.Control | Should -Be 0
            }
        }

        Context 'step 1, colours' {
            It 'offers the 20 colour slots of a scheme, and not its name' {
                $slots = @(Get-CreatorColorSlots)
                $slots.Count | Should -Be 20
                $slots | Should -Not -Contain 'name'
                $slots[0] | Should -BeExactly 'background'
            }

            It 'Right on a slot raises its lightness by 3%, asks for a preview and marks it edited' {
                $s = & $script:onStep 1
                $slots = @(Get-CreatorColorSlots)
                $i = [array]::IndexOf($slots, 'red')
                $r = @{ State = $s }
                for ($n = 0; $n -lt $i; $n++) { $r = & $script:key $r.State 'DownArrow' $null }
                $before = ConvertTo-PaletteHsl (ConvertTo-NormalHex $s.Scheme.red)
                $r = & $script:key $r.State 'RightArrow' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.Edited.Contains('red') | Should -BeTrue
                $after = ConvertTo-PaletteHsl $r.State.Scheme.red
                ($after[2] - $before[2]) | Should -BeGreaterThan 0.025
                ($after[2] - $before[2]) | Should -BeLessThan 0.035
                $r = & $script:key $r.State 'LeftArrow' $null
                $r.Action | Should -BeExactly 'preview'
                $back = ConvertTo-PaletteHsl $r.State.Scheme.red
                [Math]::Abs($back[2] - $before[2]) | Should -BeLessThan 0.006
            }

            It 'Shift+Right moves the hue by 10 degrees, from a ConsoleKeyInfo' {
                $s = & $script:onStep 1
                $s.Control = [array]::IndexOf(@(Get-CreatorColorSlots), 'red')
                Set-CreatorColor -State $s -Slot red -Hex '#c03030'
                $k = New-Object System.ConsoleKeyInfo ([char]0), ([ConsoleKey]::RightArrow), $true, $false, $false
                $r = & $script:key $s $k $null
                $r.Action | Should -BeExactly 'preview'
                $h = ConvertTo-PaletteHsl $r.State.Scheme.red
                [Math]::Round($h[0]) | Should -Be 10
            }

            It 'Shift+Left works as a string key name too' {
                $s = & $script:onStep 1
                $s.Control = [array]::IndexOf(@(Get-CreatorColorSlots), 'red')
                Set-CreatorColor -State $s -Slot red -Hex '#c03030'
                $r = & $script:key $s 'Shift+LeftArrow' $null
                [Math]::Round((ConvertTo-PaletteHsl $r.State.Scheme.red)[0]) | Should -Be 350
            }

            It 'H opens hex entry; Enter applies it through Set-CreatorColor' {
                $s = & $script:onStep 1
                $s.Control = [array]::IndexOf(@(Get-CreatorColorSlots), 'blue')
                $r = & $script:key $s 'H' $null
                $r.State.HexEntry | Should -BeExactly ''
                $r = & $script:key $r.State $null '#123456'
                $r.State.HexEntry | Should -BeExactly '#123456'
                $r = & $script:key $r.State 'Enter' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.Scheme.blue | Should -BeExactly '#123456'
                $r.State.Edited.Contains('blue') | Should -BeTrue
                $r.State.HexEntry | Should -BeNullOrEmpty
                $r.State.Step | Should -Be 1
            }

            It 'a bad hex is an error, changes nothing, and keeps the entry open' {
                $s = & $script:onStep 1
                $before = $s.Scheme.background
                $r = & $script:key $s 'H' $null
                $r = & $script:key $r.State $null 'zz'
                $r = & $script:key $r.State 'Enter' $null
                $r.Action | Should -BeExactly "error:'zz' is not a colour. Type a colour as #rrggbb."
                $r.State.Scheme.background | Should -BeExactly $before
                $r.State.Edited.Count | Should -Be 0
                $r.State.HexEntry | Should -BeExactly 'zz'
            }

            It 'Enter on an empty hex entry asks for a colour, not a binding error' {
                $s = & $script:onStep 1
                $before = $s.Scheme.background
                $r = & $script:key $s 'H' $null
                $r = & $script:key $r.State 'Enter' $null
                $r.Action | Should -BeExactly 'error:Type a colour as #rrggbb.'
                $r.State.HexEntry | Should -BeExactly ''
                $r.State.Scheme.background | Should -BeExactly $before
                $r.State.Edited.Count | Should -Be 0
            }

            It 'Esc leaves hex entry, not the creator' {
                $s = & $script:onStep 1
                $before = $s.Scheme.background
                $r = & $script:key $s 'H' $null
                $r = & $script:key $r.State $null '#000000'
                $r = & $script:key $r.State 'Escape' $null
                $r.Action | Should -Not -BeExactly 'cancel'
                $r.State.HexEntry | Should -BeNullOrEmpty
                $r.State.Step | Should -Be 1
                $r.State.Scheme.background | Should -BeExactly $before
            }

            It 'Backspace in hex entry deletes a character and does not go back' {
                $s = & $script:onStep 1
                $r = & $script:key $s 'H' $null
                $r = & $script:key $r.State $null '#12'
                $r = & $script:key $r.State 'Backspace' $null
                $r.State.HexEntry | Should -BeExactly '#1'
                $r.State.Step | Should -Be 1
            }

            It 'P re-pulls the palette and keeps an edited background' {
                $s = & $script:onStep 1
                $pulledGreen = $s.Scheme.green
                Set-CreatorColor -State $s -Slot background -Hex '#203040'
                $s.Scheme.green = '#000001'
                $r = & $script:key $s 'P' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.Scheme.background | Should -BeExactly '#203040'
                $r.State.Scheme.green | Should -BeExactly $pulledGreen
            }

            It 'the page shows the warnings under the controls' {
                $s = & $script:onStep 1
                Set-CreatorColor -State $s -Slot red -Hex $s.Scheme.background
                $text = (Get-CreatorPageLines -State $s) -join "`n"
                $text.Contains('red is hard to read against the background.') | Should -BeTrue
                $plain = (Get-CreatorPageLines -State (& $script:onStep 1)) -join "`n"
                $plain.Contains('hard to read') | Should -BeFalse
            }
        }

        Context 'step 2, font and cursor' {
            It 'Right on font size adds 1, clamped to 6..36' {
                $s = & $script:onStep 2
                $r = & $script:key $s 'DownArrow' $null
                $r = & $script:key $r.State 'RightArrow' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.FontSize | Should -Be 12
                $r.State.FontSize = 36
                $r = & $script:key $r.State 'RightArrow' $null
                $r.State.FontSize | Should -Be 36
                $r.State.FontSize = 6
                $r = & $script:key $r.State 'LeftArrow' $null
                $r.State.FontSize | Should -Be 6
            }

            It 'the cursor shape cycles in the listed order' {
                $s = & $script:onStep 2
                $r = & $script:key $s 'DownArrow' $null
                $r = & $script:key $r.State 'DownArrow' $null
                $seen = @()
                for ($i = 0; $i -lt 6; $i++) {
                    $r = & $script:key $r.State 'RightArrow' $null
                    $seen += $r.State.CursorShape
                }
                $seen | Should -Be @('vintage', 'underscore', 'filledBox', 'emptyBox', 'doubleUnderscore', 'bar')
            }

            It 'the font face changes with Right' {
                $s = & $script:onStep 2
                $r = & $script:key $s 'RightArrow' $null
                $r.Action | Should -BeExactly 'preview'
                $r.State.FontFace | Should -Not -BeExactly 'Cascadia Code'
            }
        }

        Context 'step 3, prompt' {
            It 'the shape cycles through Get-StylePromptShapes' {
                $s = & $script:onStep 3
                $seen = @()
                foreach ($i in 1..4) {
                    $r = & $script:key $s 'RightArrow' $null
                    $s = $r.State
                    $seen += $s.PromptShape
                }
                $seen | Should -Be @('path', 'twoline', 'git', 'minimal')
            }

            It 'the symbol only ever takes Get-StylePromptSymbols'' values' {
                $s = & $script:onStep 3
                $s.Control = 1
                $offered = @(Get-StylePromptSymbols)
                $seen = @()
                foreach ($i in 1..$offered.Count) {
                    $s = (& $script:key $s 'RightArrow' $null).State
                    $seen += $s.Symbol
                }
                @($seen | Sort-Object -Unique).Count | Should -Be $offered.Count
                foreach ($x in $seen) { $offered -ccontains $x | Should -BeTrue }
                $r = & $script:key $s $null '%'
                $r.State.Symbol | Should -BeExactly $s.Symbol
                $r.Action | Should -BeExactly 'none'
            }

            It 'the path and symbol colours cycle through the scheme''s colours' {
                $s = & $script:onStep 3
                $s.Control = 2
                $before = $s.PromptPathColor
                $r = & $script:key $s 'RightArrow' $null
                $r.State.PromptPathColor | Should -Not -BeExactly $before
                $r.State.PromptPathColor | Should -Match '^#[0-9a-f]{6}$'
                $r.State.Control = 3
                $b2 = $r.State.PromptSymbolColor
                $r = & $script:key $r.State 'LeftArrow' $null
                $r.State.PromptSymbolColor | Should -Not -BeExactly $b2
            }
        }

        Context 'step 4, name' {
            It 'typed characters fill the name, and Backspace only deletes them, even on an empty name' {
                $s = & $script:onStep 4
                $r = & $script:key $s $null 'ab'
                $r.State.Name | Should -BeExactly 'ab'
                $r = & $script:key $r.State 'Backspace' $null
                $r.State.Name | Should -BeExactly 'a'
                $r.State.Step | Should -Be 4
                $r = & $script:key $r.State 'Backspace' $null
                $r.State.Step | Should -Be 4
                $r = & $script:key $r.State 'Backspace' $null
                $r.Action | Should -BeExactly 'none'
                $r.State.Step | Should -Be 4
                $r.State.Name | Should -BeExactly ''
            }

            It 'PageUp on step 4 goes back to step 3' {
                $s = & $script:onStep 4
                $s.Name = 'keep'
                $r = & $script:key $s 'PageUp' $null
                $r.Action | Should -BeExactly 'back'
                $r.State.Step | Should -Be 3
                $r.State.Name | Should -BeExactly 'keep'
            }

            It 'PageUp arrives as a ConsoleKeyInfo too' {
                $k = New-Object System.ConsoleKeyInfo ([char]0), ([ConsoleKey]::PageUp), $false, $false, $false
                $r = & $script:key (& $script:onStep 4) $k $null
                $r.State.Step | Should -Be 3
            }

            It 'a bundled style''s name is refused as taken' {
                $s = & $script:onStep 4
                $s.Name = 'sober'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeLike 'error:*'
                $r.Action.Contains("'sober'") | Should -BeTrue
                $r.Action.Contains('taken') | Should -BeTrue
                $r.State.Step | Should -Be 4
            }

            It 'the user''s own style''s name is refused as taken' {
                $dir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'mine'
                [void][System.IO.Directory]::CreateDirectory($dir)
                [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), '{}')
                $s = & $script:onStep 4
                $s.Name = 'mine'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeLike "error:*'mine'*taken*"
            }

            It 'an invalid name is refused with the naming rule' {
                $s = & $script:onStep 4
                $s.Name = '..'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeLike 'error:*letters, digits*'
            }

            It 'an empty name asks for one' {
                $s = & $script:onStep 4
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeLike 'error:*'
                $r.State.Step | Should -Be 4
            }

            It 'a free, valid name returns save' {
                $s = & $script:onStep 4
                $s.Name = 'my-style'
                $r = & $script:key $s 'Enter' $null
                $r.Action | Should -BeExactly 'save'
                $r.State.Name | Should -BeExactly 'my-style'
            }
        }
    }
}

Describe 'Get-CreatorPageLines' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:px = [int[]]@(
                foreach ($c in 0x0a0a2a, 0xff7a1a, 0x3060d0, 0x2fa04a, 0xe0e0f0) { for ($i = 0; $i -lt 30; $i++) { $c } }
            )
            $script:plain = { param($lines) ((@($lines) -join "`n") -replace "$([char]27)\[[0-9;]*m", '') }
        }
        BeforeEach {
            # A folder with a name nobody would put in the sample, so a leak of
            # the real location shows.
            $script:leaf = 'leafprobe' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $script:where = Join-Path $TestDrive $script:leaf
            [void][System.IO.Directory]::CreateDirectory($script:where)
            Push-Location -LiteralPath $script:where
        }
        AfterEach { Pop-Location }

        It 'step 3 with the git shape and U+276F shows the fixed sample, not the real folder' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 3
            $s.PromptShape = 'git'
            $s.Symbol = [string][char]0x276F
            $lines = Get-CreatorPageLines -State $s
            ,$lines | Should -BeOfType [string[]]
            $text = & $script:plain $lines
            $text.Contains('projects') | Should -BeTrue
            $text.Contains('(main)') | Should -BeTrue
            $text.Contains([string][char]0x276F) | Should -BeTrue
            $text.Contains($script:leaf) | Should -BeFalse
            $text.Contains((Split-Path -Leaf $PWD.Path)) | Should -BeFalse
        }

        It 'the sample session has the git status and the ls' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 2
            $text = & $script:plain (Get-CreatorPageLines -State $s)
            $text.Contains('git status') | Should -BeTrue
            $text.Contains('modified: readme.md') | Should -BeTrue
            $text.Contains('deleted:  old.txt') | Should -BeTrue
            $text.Contains('src  docs  build.ps1') | Should -BeTrue
            # One line per element: a nested array would be joined with spaces.
            $each = @(Get-CreatorPageLines -State $s | ForEach-Object { $_ -replace "$([char]27)\[[0-9;]*m", '' })
            @($each | Where-Object { $_ -ceq 'On branch main' }).Count | Should -Be 1
            @($each | Where-Object { $_ -ceq 'src  docs  build.ps1' }).Count | Should -Be 1
        }

        It 'the shapes render as the spec lists them' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 3
            $s.PromptShape = 'path'
            (& $script:plain (Get-CreatorPageLines -State $s)).Contains('~/code/projects $') | Should -BeTrue
            $s.PromptShape = 'minimal'
            $t = & $script:plain (Get-CreatorPageLines -State $s)
            $t.Contains('projects $') | Should -BeTrue
            $t.Contains('~/code/projects') | Should -BeFalse
            $s.PromptShape = 'twoline'
            $t = & $script:plain (Get-CreatorPageLines -State $s)
            $t.Contains("~/code/projects`n$") | Should -BeTrue
        }

        It 'the controls come before the sample session' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 2
            $text = & $script:plain (Get-CreatorPageLines -State $s)
            $text.Contains('PgUp or Backspace previous step') | Should -BeTrue
            $text.IndexOf('Font size') | Should -BeGreaterThan -1
            $text.IndexOf('Font size') | Should -BeLessThan $text.IndexOf('git status')
        }

        It 'step 0 before an image shows the path field and the sample session' {
            $s = New-CreatorStartState
            $s.PathText = 'C:\pics\x.png'
            $text = & $script:plain (Get-CreatorPageLines -State $s)
            $text.Contains('C:\pics\x.png') | Should -BeTrue
            $text.Contains('git status') | Should -BeTrue
            $text.Contains('Opacity') | Should -BeFalse
        }

        It 'step 0 after an image shows the image settings' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $text = & $script:plain (Get-CreatorPageLines -State $s)
            $text.Contains('Opacity') | Should -BeTrue
            $text.Contains('0.35') | Should -BeTrue
            $text.Contains('uniformToFill') | Should -BeTrue
        }

        It 'step 1 hex entry shows what is typed' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 1
            $s.HexEntry = '#12'
            (& $script:plain (Get-CreatorPageLines -State $s)).Contains('#12') | Should -BeTrue
        }

        It 'step 4 shows the typed name and any warnings before save' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Step = 4
            $s.Name = 'probe-name'
            Set-CreatorColor -State $s -Slot red -Hex $s.Scheme.background
            $text = & $script:plain (Get-CreatorPageLines -State $s)
            $text.Contains('probe-name') | Should -BeTrue
            $text.Contains('PgUp previous step') | Should -BeTrue
            $text.Contains('red is hard to read') | Should -BeTrue
        }
    }
}
