# Security Policy

## Supported Versions

Only the latest release is actively maintained with security fixes.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

Please do **not** open a public issue for security vulnerabilities.

Instead, report them privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
via the **Security → Report a vulnerability** tab of this repository.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (proof of concept if possible)
- Affected version(s) and platform
- Any suggested remediation

## Response Expectations

- Acknowledgement of your report within **5 business days**
- An assessment and, where applicable, a fix timeline
- Credit in the release notes unless you prefer to remain anonymous

## Scope

CallerLite is a SIP softphone. Areas of particular interest include:

- Credential handling and storage (SIP account passwords)
- Audio capture / microphone permission handling
- Network parsing of SIP messages and media streams

Thank you for helping keep CallerLite and its users safe.
