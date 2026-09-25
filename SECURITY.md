# Security policy

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/omar-hanafy/Resolute/security/advisories/new). Private reporting is enabled for this repository. Do not include exploit details, credentials or sensitive diagnostics in a public issue.

Include the affected version or commit, macOS version, reproduction steps, expected and actual behavior, and the impact. Redact personal paths and display identifiers from logs. Ordinary bugs belong in [Issues](https://github.com/omar-hanafy/Resolute/issues).

## Supported versions and boundaries

Resolute is currently a beta. Security fixes target the latest source on `main` and the current beta release; older development versions have no promised backports or response-time guarantee.

Mode switching and administrator-approved override changes affect display configuration. Follow the recovery guidance and [validation limits](docs/production-readiness.md). The 0.3.0 beta binaries are ad hoc signed and not notarized; a published download is not evidence of Gatekeeper approval or complete hardware coverage.
