# - Security Policy -

## Supported versions

| Version                | Supported                              |
| ---------------------- | -------------------------------------- |
| 0.6.x (latest release) | ✅                                      |
| older                  | ❌ — update first (`tstyles update`)    |

## Reporting a vulnerability

Please report vulnerabilities privately — do not open a public issue.

- **Preferred:** GitHub private vulnerability reporting — open the
  [Security tab](https://github.com/fcreme/TerminalStyles/security) and click
  "Report a vulnerability".
- **Fallback:** email felipecremerius1@gmail.com.

This is a maintainer-run hobby project: responses are best-effort, usually
within a few days. There is no bug bounty.

## Scope

TerminalStyles writes to your PowerShell `$PROFILE` and Windows Terminal's
`settings.json`, fetches background images over HTTPS, and (on bootstrap
installs only) runs an unauthenticated daily update check against the GitHub
API. Reports about those write/fetch paths — profile injection, settings
corruption, update-check tampering — are explicitly welcome.
