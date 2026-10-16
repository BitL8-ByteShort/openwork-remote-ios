# Security

## Report privately

Use [GitHub's private vulnerability report](https://github.com/BitL8-ByteShort/openwork-remote-ios/security/advisories/new). Include the commit, synthetic reproduction steps and expected versus observed behavior. Don't include a working credential, pairing link, transcript, private hostname or signing file.

If private reporting isn't available, email **support@saltypanda.com** to arrange a private report. There is no promised response time or security support contract. A problem in OpenCode or OpenTunnel should also be reported privately to that project's maintainers.

## Native candidate scope

The source candidate accepts inspected native profiles **2.0.29** and **2.0.30**, with separately recorded Mac and Linux checks. Official stock2.0.30 password/pairing and typed API qualification uses isolated loopback runtimes; normal Release phone HTTPS password pairing/reload uses the isolated2.0.29 host. Unknown patch versions remain unverified. Complete physical-device and public-release qualification remains pending. Earlier OpenWork beta binaries have a different security boundary; their scoped bridge permissions do not describe this native connection.

A native pairing code is short-lived and single-use. Redemption provides a saved credential with **server-wide access**, including supported project/file operations. It is not a per-phone, per-project sandbox. Project visibility and future-project choices are local display filters. Pair only a server you are authorized to access.

The optional source-candidate password route reviews the exact HTTPS origin before transmitting the standard server password. It issues and redeems a fresh native code, then clears that password; PocketWork persists only the issued paired credential. Apple's optional Passwords saving is a separate system choice. A known narrow-iPad password/background crash currently holds the next beta.

The credential is stored in the iOS Keychain. Requests use the selected HTTPS origin, normal certificate validation and redirect blocking. No arbitrary request-forwarding or shell endpoint is added by PocketWork. OpenCode can route remote traffic through OpenTunnel. Host software, plugins, configuration and model providers remain part of the trust boundary.

**Forget and local reset do not revoke server access.** The tested native version has no individual phone-revocation contract. Server-password rotation invalidates shared paired credentials and affects other devices; it is not an automatic recovery step. Reset also does not stop remote work or delete host chats, staged uploads, exported copies or other devices' data.

## Actions and data

Required approvals and questions remain outside compact Activity. Allow actions require review; unavailable or unsupported controls hand off to the computer. Lost responses keep an uncertain outcome and are not automatically replayed.

Provider review describes the reported configuration and any routing uncertainty. A provider alias is not proof of a local or verified final destination. Upload preparation may already place document bytes on the host before Send. Removing a selection or resetting the phone does not promise to remove those host bytes.

Local snapshots, drafts and downloaded copies use protected storage. Reset reports failures rather than claiming deletion succeeded. A compromised/unlocked device or host is outside a promise of remote isolation. See the candidate's [privacy text](OpenWorkRemote/Resources/Information/privacy.txt) for the implemented data handling.

## Repository controls

The repository is public for reading and contributions; direct write access is owner-controlled. On October 15, classic main-branch protection required **Source checks** and **Simulator build**, applied to administrators, blocked force pushes and deletion, and dismissed stale reviews. It did not require a second approving reviewer. These settings are separate from GitHub rulesets.

Actions use read-only repository tokens and pinned checkout actions. Signing secrets are not required by CI. Secret scanning and push protection are enabled. No protection substitutes for reviewing a change. Never commit credentials, certificates, provisioning profiles, real device state, private transcripts or real pairing payloads.
