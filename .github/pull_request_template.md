## What and why

<!-- What does this change, and what problem does it solve?
     Link the issue if there is one: Fixes #12 -->

## Checklist

- [ ] `Invoke-Pester -Path tests` is green locally on at least one engine — CI runs both pwsh 7 and Windows PowerShell 5.1
- [ ] New behavior has tests
- [ ] The diff stays focused on one change

## Theme PRs

<details>
<summary>Extra checklist if this PR adds or changes a theme (skip otherwise)</summary>

- [ ] `scheme.json` has a `name` that is unique across every bundled theme
- [ ] `scheme.json` has the full Windows Terminal key set (`styles/gitbash/scheme.json` shows it)
- [ ] Every color is 6-digit `#rrggbb` hex — no `#fff` shorthand
- [ ] Contrast floor passes locally: `Invoke-Pester -Path tests/Scheme-Contrast.Tests.ps1` (every chromatic ANSI color above 3:1 against the scheme background)
- [ ] No background binary on `main` — `tests/No-Committed-Backgrounds.Tests.ps1` fails CI if one sneaks in
- [ ] If the theme ships a background: the image sits flat at the root of the `gifs` branch as `<name>.<ext>`, under ~2 MB
- [ ] I have the right to redistribute any image in this PR
- [ ] README catalog entry added and screenshot regenerated via `scripts/capture-screenshots.ps1` (the maintainer can capture it if you can't run Windows Terminal)

</details>
