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

Email **felipecremerius1@gmail.com**. Please include the version
(`(Get-Module TerminalStyles).Version`, or `Get-Module -ListAvailable
TerminalStyles` if it is not loaded), your OS and terminal, and the steps to
reproduce.

GitHub private vulnerability reporting is **not currently enabled** on this
repository, so there is no "Report a vulnerability" button on the Security
tab — email is the channel. (This document previously named that button as
the preferred route, which sent reporters to a page that does not offer it.)

This is a maintainer-run hobby project: responses are best-effort, usually
within a few days. There is no bug bounty.

## Scope

TerminalStyles writes to your PowerShell `$PROFILE` and Windows Terminal's
`settings.json`, fetches background images over HTTPS, and (on bootstrap
installs only) runs an unauthenticated daily update check against the GitHub
API. Reports about those write/fetch paths — profile injection, settings
corruption, update-check tampering — are explicitly welcome.
