# Security Policy

## Supported version

Security fixes are applied to the newest release line.

## Reporting a vulnerability

Please report security issues privately to `vikas0vks` through the contact option on the repository owner's GitHub profile. Do not include private keys, signing credentials, personal files, or third-party data in a public issue.

Include the affected version, platform, exact reproduction steps, observed impact, and the smallest safe proof needed to confirm the issue. Reports are acknowledged after reproduction and are disclosed only after a fix is available.

## Scope

Relevant areas include LAN discovery, TLS identity, trusted-device behavior, Web Share, transfer authorization, filename and path handling, resume/cancel state, Android components, installers, and local data protection.

The update checker contacts only the public `vikas0vks/suvishare` GitHub Releases endpoint. It accepts bounded release metadata and trusted HTTPS GitHub links, never downloads or executes an installer silently, and does not send file metadata or analytics.
