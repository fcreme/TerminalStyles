# - Security Policy -

## Supported versions

| Version                | Supported                              |
| ---------------------- | -------------------------------------- |
| 0.8.x (latest release) | ✅                                      |
| older                  | ❌ — update first (`tstyles update`)    |

Only the latest release is supported. Fixes ship forward in a new version
rather than being backported.

## Reporting a vulnerability

Please report vulnerabilities privately — do not open a public issue.

- **Preferred:** GitHub private vulnerability reporting — open the
  [Security tab](https://github.com/fcreme/TerminalStyles/security) and click
  **Report a vulnerability**. This is enabled on the repository, so the button
  is there.
- **Fallback:** email **felipecremerius1@gmail.com**.

Either way, please include the version (`(Get-Module TerminalStyles).Version`,
or `Get-Module -ListAvailable TerminalStyles` if it is not loaded), your OS and
terminal, and the steps to reproduce.

This is a maintainer-run hobby project: responses are best-effort, usually
within a few days. There is no bug bounty.

## Scope

TerminalStyles writes to your PowerShell `$PROFILE` and Windows Terminal's
`settings.json`, fetches background images over HTTPS, and (on bootstrap
installs only) runs an unauthenticated daily update check against the GitHub
API. Reports about those write/fetch paths — profile injection, settings
corruption, update-check tampering — are explicitly welcome.
