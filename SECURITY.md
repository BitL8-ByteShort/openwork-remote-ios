# Security

## Report a vulnerability privately

Use [GitHub's private vulnerability report](https://github.com/BitL8-ByteShort/openwork-remote-ios/security/advisories/new). Include the affected commit, reproduction steps, and expected versus observed behavior. Use synthetic data. Don't post a working token, pairing secret, transcript, private hostname, or signing file.

If private reporting is unavailable, open an issue asking for a private contact without describing the vulnerability. There is no promised response time or security support contract for this early project.

## Scope and supported versions

Security fixes target the latest main branch. There are no supported binary release channels yet. Report desktop bridge problems privately to the maintainers of the repository containing that bridge; don't put an exploit in a public cross-repository issue.

The phone receives a device credential scoped by the host. Pairing requires approval on the computer. Selecting all future projects is an explicit choice, not the default. The phone cannot broaden its own scope or automatically approve tool execution.

The bridge belongs on loopback behind private Tailscale HTTPS. Public Funnel endpoints, disabled certificate checks, generic proxy routes, and remote shell endpoints are outside the supported design. The computer and its user account remain trusted. A compromised host or a deliberately permissive project scope can expose that scope's data.

Host feature availability, model availability, and approval support are enforced by the host. Required approvals remain visible when tool activity is collapsed. Ambiguous network failures must be reconciled before retrying a write.

## Repository controls

Contributions go through pull requests and required checks. Actions use read-only repository tokens and don't need signing secrets. External contributors don't receive direct write access. Certificates, provisioning profiles, API keys, device state, transcripts, and real pairing payloads must never be committed.
