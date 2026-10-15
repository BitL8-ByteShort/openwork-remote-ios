# Moving from the OpenWork beta

The OpenCode migration is a new connection backend for the existing PocketWork app. It keeps the app identity. It does not convert the earlier OpenWork pairing into an OpenCode credential.

The native1.0.0(9) beta is available to the existing internal TestFlight group. Update there. No cable is required. Keep a copy of important unsent text before changing connections. The native candidate starts with OpenCode pairing, using **Remote access → Pair device** in a compatible OpenCode installation. The inspected baseline is 2.0.29.

Earlier recoverable draft text stays local and separate. Open **Data Controls** to review it, select the intended native chat/folder and deliberately copy the text. Attachments, selected skills and uncertain actions are not transferred. Opening the app never resends an old prompt. A saved native chat selection is checked against its actual folder before restoration; moved-folder text requires review.

## Permissions changed

The earlier beta's scoped device grants do not carry across. The native OpenCode credential grants server-wide access. Project visibility and Show future projects affect the phone's lists only. Review chat rules and tool approvals separately. **Forget** and local reset do not revoke that server credential or stop remote work.

## Clear or reset

Data Controls separately clears unsent text, downloaded copies or sharing permissions. Full reset removes native and earlier credentials plus recognized app data, and reports partial failures. It preserves unknown files rather than claiming deletion. It does not delete host chats, staged uploads, exported copies or other devices' data.

Native1.0.0 betas are distributed through the existing internal group; earlier0.1.0 builds use OpenWork. Public App Store release remains pending. See [compatibility](opencode-compatibility.md) and [Security](../SECURITY.md).

## Updating from native build8

Build9 keeps the native pairing and existing chats. It fixes new-chat identifiers rejected by OpenCode’s free-model service and an immediate delivery-warning banner during a normal send. Create a new chat in PocketWork after updating to test the identifier fix. Earlier chat IDs and uncertain actions are preserved. A genuine unknown delivery still requires checking the conversation before trying again; the app never resends automatically.
