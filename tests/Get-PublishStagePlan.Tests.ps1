# Pester 5 tests for Get-PublishStagePlan (scripts/Get-PublishStagePlan.ps1).
#
# The publish stage plan must be driven by what git TRACKS, not by what happens
# to sit in the working directory. Runtime cache (styles/*/background.gif, the
# .no-background markers) is gitignored but lives in a normal checkout, and a
# plain Copy-Item of the styles/ tree would bundle megabytes of it into the
# PSGallery package -- differently on every maintainer's machine.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'scripts\Get-PublishStagePlan.ps1')

    $script:enc = [System.Text.UTF8Encoding]::new($false)

    function script:New-File {
        param([string]$Path, [string]$Content = 'x')
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Path, $Content, $script:enc)
    }

    # Windows PowerShell 5.1 turns anything a native command writes to stderr
    # into an error record, which is TERMINATING under $ErrorActionPreference
    # = 'Stop' (Pester's default inside test blocks). git chats on stderr for
    # perfectly successful commands -- CRLF warnings, the default-branch hint --
    # so route it to $null and trust the exit code instead.
    function script:Invoke-Git {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
        & git @GitArgs 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed ($LASTEXITCODE)" }
    }

    # A throwaway git repo mirroring the real layout: tracked theme files plus
    # a gitignored background.gif and .no-background marker sitting on disk.
    function script:New-FixtureRepo {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        script:New-File (Join-Path $root '.gitignore') "styles/**/background.*`nstyles/**/.no-background`n"
        script:New-File (Join-Path $root 'TerminalStyles.psd1') '@{}'
        script:New-File (Join-Path $root 'fonts.json') '{"fonts":[]}'
        script:New-File (Join-Path $root 'styles\eva\theme.json') '{}'
        script:New-File (Join-Path $root 'styles\eva\profile.ps1') '# eva'
        script:New-File (Join-Path $root 'styles\rain\theme.json') '{}'
        script:New-File (Join-Path $root 'scripts\capture-screenshots.ps1') '# cap'

        script:Invoke-Git -C $root init --quiet
        script:Invoke-Git -C $root config user.email 'test@example.com'
        script:Invoke-Git -C $root config user.name  'Test'
        # Keep line endings verbatim so `git add` has no CRLF warning to emit.
        script:Invoke-Git -C $root config core.autocrlf false
        script:Invoke-Git -C $root add -A
        script:Invoke-Git -C $root commit -m init --quiet

        # Runtime cache lands AFTER the commit -- untracked and ignored.
        script:New-File (Join-Path $root 'styles\eva\background.gif') 'GIF89a-pretend-binary'
        script:New-File (Join-Path $root 'styles\rain\.no-background') ''

        return $root
    }
}

Describe 'Get-PublishStagePlan' {
    BeforeAll {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $script:noGit = $true
        }
    }

    BeforeEach {
        if ($script:noGit) { Set-ItResult -Skipped -Because 'git is not available'; return }
        $script:root = script:New-FixtureRepo
    }

    It 'returns tracked files for a directory allowlist entry' {
        $plan = Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('styles')
        $plan | Should -Contain 'styles/eva/theme.json'
        $plan | Should -Contain 'styles/eva/profile.ps1'
        $plan | Should -Contain 'styles/rain/theme.json'
    }

    It 'excludes gitignored runtime cache sitting in the working directory' {
        $plan = Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('styles')
        # The files really are on disk -- the plan just must not pick them up.
        Test-Path (Join-Path $script:root 'styles\eva\background.gif') | Should -BeTrue
        ($plan | Where-Object { $_ -like '*background.gif' }) | Should -BeNullOrEmpty
        ($plan | Where-Object { $_ -like '*.no-background' })  | Should -BeNullOrEmpty
    }

    It 'returns a single tracked file for a file allowlist entry' {
        $plan = Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('fonts.json')
        @($plan).Count | Should -Be 1
        $plan[0] | Should -Be 'fonts.json'
    }

    It 'accepts backslash-separated allowlist entries' {
        $plan = Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('scripts\capture-screenshots.ps1')
        $plan | Should -Contain 'scripts/capture-screenshots.ps1'
    }

    It 'preserves allowlist order and de-duplicates overlapping entries' {
        $plan = Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('fonts.json', 'styles', 'fonts.json')
        @($plan | Where-Object { $_ -eq 'fonts.json' }).Count | Should -Be 1
        $plan[0] | Should -Be 'fonts.json'
    }

    It 'throws when an allowlist item does not exist at all' {
        { Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('nope.txt') } |
            Should -Throw '*nope.txt*'
    }

    It 'throws when an allowlist item exists on disk but is untracked' {
        # Guards the inverse mistake: shipping a new file that was never committed.
        script:New-File (Join-Path $script:root 'brand-new.ps1') '# forgot to commit'
        { Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('brand-new.ps1') } |
            Should -Throw '*brand-new.ps1*'
    }

    It 'throws when a DIRECTORY entry hides an untracked file' {
        # The gap the directory entries were supposed to close, and did not. The
        # zero-count guard above only fires when the WHOLE entry resolves to
        # nothing, so 'styles' -- which resolves to plenty -- sailed past it while
        # a forgotten `git add` sat inside. lib/*.ps1 is dot-sourced by
        # enumeration, so that ships a module which imports cleanly and then dies
        # at first use.
        script:New-File (Join-Path $script:root 'styles\newtheme\theme.json') '{}'
        { Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('styles') } |
            Should -Throw '*newtheme*'
    }

    It 'still stays silent about gitignored cache inside a directory entry' {
        # The distinction the guard above must not blur: background.gif and
        # .no-background are untracked too, and skipping them silently is the
        # entire reason this helper exists. Only untracked-and-NOT-ignored is an
        # error.
        { Get-PublishStagePlan -RepoRoot $script:root -Allowlist @('styles') } |
            Should -Not -Throw
        Test-Path (Join-Path $script:root 'styles\eva\background.gif') | Should -BeTrue
    }

    It 'throws when the repo root is not a git checkout' {
        $bare = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $bare -Force | Out-Null
        script:New-File (Join-Path $bare 'fonts.json') '{}'
        { Get-PublishStagePlan -RepoRoot $bare -Allowlist @('fonts.json') } |
            Should -Throw '*git*'
    }
}
